"""Bounded full-output real-Jac MatMul experiment (CPU packing unless --cuda)."""
import argparse
from array import array
import gc
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from compare_named_layouts import schemas_and_modules, memory_context
from layout_benchmark import permute_cursors, permutation
from bounded import build_inputs, planning_bindings, axis_heads, bind, digest, guard, rss, Resident


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--shape', default='64x3000x64')
    parser.add_argument('--batch', type=int, default=32768)
    parser.add_argument('--max-input-nodes', type=int, default=1000000)
    parser.add_argument('--rss-budget-gib', type=float, default=8)
    parser.add_argument('--seeds', type=int, nargs='+', default=[928, 929, 930])
    parser.add_argument('--cuda', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    m,k,n = map(int, args.shape.split('x'))
    node_count = (m+n)*k
    if min(m,k,n,args.batch)<1 or node_count>args.max_input_nodes or args.batch>32768:
        parser.error('Positive sizes, explicit node admission limit, batch <= 32768 required')
    args.output.mkdir(parents=True, exist_ok=True)
    snapshot=args.output/'source';snapshot.mkdir(exist_ok=True)
    for source in Path(__file__).parent.glob('*.py'):
        (snapshot/source.name).write_bytes(source.read_bytes())
    report = dict(shape=[m,k,n], full_outputs=m*n, MACs=m*k*n,
                  input_nodes=node_count, edges=(m+n)*(k-1), batch_size=args.batch,
                  output_node_policy='real one-int Scalar output nodes materialized per bounded batch, saved to binary then released',
                  weights='A[i,k]=i+1; B[k,j]=j+1', dtype='int64',
                  queue_capacity=1, queue_proof='one seed; pop before at most one append per cursor; pending <= 1',
                  actual_CPU_graph=True, CUDA=args.cuda, phases=[], layouts=[],
                  git_head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
                  source_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in Path(__file__).parent.glob('*.py')})
    def save():
        path=args.output/'report.json'
        tmp=args.output/'report.pending.json'
        tmp.write_text(json.dumps(report,indent=2)+'\n');tmp.replace(path)
    def monitor():
        while True:
            try:
                guard(args.rss_budget_gib)
            except MemoryError as error:
                (args.output/'resource-guard-failure.json').write_text(json.dumps(dict(error=str(error),**rss())))
                os._exit(102)
            time.sleep(.25)
    threading.Thread(target=monitor,daemon=True).start()
    schemas, modules = schemas_and_modules(['Dot']);schema=schemas['Dot'];mod=modules['Dot']
    report['ptx_sha256']=hashlib.sha256(schema.ptx.encode()).hexdigest()
    (args.output/'Dot.ptx').write_text(schema.ptx)
    save()
    with memory_context():
        started=time.perf_counter();heads=build_inputs(mod,m,k,n,args.rss_budget_gib)
        report['phases'].append(dict(stage='real_Jac_input_graph',wall_s=time.perf_counter()-started,**rss()));save()
        walkers, starts=planning_bindings(mod,heads)
        report['layout_planning_seed_lanes']=len(walkers)
        report['planning_equivalence']='first occurrences match full row-major batch seeds in both channel and union discovery order'
        for layout in ('current','predicted'):
            started=time.perf_counter()
            from jaclang.runtime import gpu_cursors
            packed=gpu_cursors.pack_cursors(schema,walkers,starts,queue_capacity=1,
                max_visits=k+1,layout=layout,prediction_budget=max(m*k,n*k),
                max_nodes=args.max_input_nodes)
            buffers=packed.buffers
            if layout=='predicted':
                channels=buffers.prediction['channels']
                if any(ch['truncated'] for ch in channels) or [ch['discovered'] for ch in channels]!=[m*k,n*k]:
                    raise AssertionError('Prediction must discover both complete cursor BFS sequences')
            if len(buffers.tags)!=node_count or len(buffers.targets)!=(m+n)*(k-1):
                raise AssertionError('Shared real graph count changed')
            if any(buffers.offsets[i+1]-buffers.offsets[i]>1 for ch in range(2)
                   for i in range(ch*(node_count+1),ch*(node_count+1)+node_count)):
                raise AssertionError('Queue-capacity-one proof requires single successors')
            order=array('q',buffers.prediction['order'])
            with (args.output/f'{layout}-identity-order.bin').open('wb') as stream:order.tofile(stream)
            info=dict(layout=layout,pack_s=time.perf_counter()-started,pack_timings=buffers.timings,
                      prediction_budget=max(m*k,n*k),prediction_channels=buffers.prediction['channels'],
                      node_count=node_count,identity_hash=digest(order),
                      array_hashes=[digest(v) for v in buffers.arrays()[:4]],
                      payload_bytes=buffers.memory_plan().payload_bytes(),**rss())
            axes=axis_heads(buffers,m,n)
            save_inputs(args.output,layout,buffers,axes,info)
            buffers.prediction={}
            del order,packed
            gc.collect()
            report['layouts'].append(info);save()
            if args.cuda:
                execute(schema,mod,buffers,axes,m,k,n,args,info,save)
            if layout=='current':
                # Canonical typed arrays retained for Random; actual Jac graph
                # stays shared and unchanged for the later Predicted pack.
                current=buffers
            else:
                del buffers
                gc.collect()
        for seed in args.seeds:
            started=time.perf_counter()
            buffers=permute_cursors(current,permutation(node_count,seed))
            order=array('q',buffers.prediction['order'])
            with (args.output/f'random-{seed}-identity-order.bin').open('wb') as stream:order.tofile(stream)
            info=dict(layout='random',seed=seed,permutation_s=time.perf_counter()-started,
                      identity_hash=digest(order),array_hashes=[digest(v) for v in buffers.arrays()[:4]],**rss())
            axes=axis_heads(buffers,m,n);buffers.prediction={};del order;gc.collect()
            save_inputs(args.output,f'random-{seed}',buffers,axes,info)
            report['layouts'].append(info);save()
            if args.cuda:execute(schema,mod,buffers,axes,m,k,n,args,info,save)
            del buffers;gc.collect()
    report['complete']=True;save()
    print(json.dumps(dict(complete=True,report=str(args.output/'report.json'))),flush=True)


def save_inputs(folder,label,buffers,axes,info):
    files=[]
    started=time.perf_counter()
    for index,values in enumerate([*buffers.arrays()[:4],*axes]):
        path=folder/f'{label}-input-{index}.bin'
        with path.open('wb') as stream:values.tofile(stream)
        files.append(dict(path=str(path.resolve()),type=values.typecode,count=len(values),sha256=digest(values)))
    info['packed_files']=files
    info['artifact_write_s']=time.perf_counter()-started


def execute(schema,mod,buffers,axes,m,k,n,args,info,save):
    started=time.perf_counter();resident=Resident(schema,buffers,min(args.batch,m*n))
    info.update(gpu=resident.session.gpu_name,driver_version=resident.session.driver_version,
                graph_H2D_s=resident.graph_h2d_s,context_and_graph_upload_s=time.perf_counter()-started,
                max_grid=resident.session.max_grid,batches=[])
    name=info['layout']+(f'-{info["seed"]}' if 'seed' in info else '')
    output_hash=hashlib.sha256()
    wall=time.perf_counter()
    try:
        with (args.output/f'{name}-outputs-int64.bin').open('wb') as stream:
            for start in range(0,m*n,args.batch):
                batch=bind(buffers,axes,start,min(args.batch,m*n-start),n)
                stats=resident.run(batch)
                expected=array('q',(k*(lane//n+1)*(lane%n+1) for lane in range(start,start+len(batch.results))))
                if batch.results!=expected:raise AssertionError(f'Full CPU oracle mismatch at batch {start}')
                output_started=time.perf_counter()
                output_nodes=[mod.Scalar(value=value) for value in batch.results]
                if any(node.value!=value for node,value in zip(output_nodes,batch.results)):
                    raise AssertionError('Jac Scalar output materialization mismatch')
                stats['output_nodes_materialize_validate_s']=time.perf_counter()-output_started
                del output_nodes
                batch.results.tofile(stream)
                output_hash.update(memoryview(batch.results).cast('B'))
                info['batches'].append(dict(start=start,count=len(batch.results),**stats))
                if len(info['batches'])%16==0:save()
        info.update(full_result=True,covered_outputs=m*n,output_sha256=output_hash.hexdigest(),
                    all_output_validation='exact independent structured integer CPU oracle',
                    execute_all_batches_wall_s=time.perf_counter()-wall)
        save()
    finally:resident.close()


if __name__=='__main__':main()
