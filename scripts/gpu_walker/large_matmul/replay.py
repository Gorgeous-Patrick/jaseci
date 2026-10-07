"""Paired CUDA replay of exact binary artifacts from a real-Jac full graph.

This samples bounded output batches, NOT a full-result run. Ordinary event and
Nsight replay runs are separate. No layout/neighbor reconstruction is performed.
"""
import argparse
from array import array
import json
import hashlib
from pathlib import Path
import random
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from compare_named_layouts import schemas_and_modules
from layout_benchmark import paired_order, summarize
from bounded import Resident, bind, digest


def load(info,schema,k):
    from jaclang.runtime.gpu_cursors import CursorBuffers
    values=[]
    for file in info['packed_files']:
        data=array(file['type'])
        with Path(file['path']).open('rb') as stream:data.fromfile(stream,file['count'])
        if digest(data)!=file['sha256']:raise ValueError('Artifact checksum mismatch')
        values.append(data)
    field,tags,offsets,targets,left,right=values
    buffers=CursorBuffers(schema.cursor_spec,[field],tags,offsets,targets,
        array('q',[left[0],right[0]]),array('q',[1,1]),array('q',[0]),array('q',[0]),
        array('I',[0]),array('q',[left[0],right[0]]),1,k+1,[],[],prediction={},timings={})
    return buffers,(left,right)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--seeds',type=int,nargs='+',default=[928,929,930])
    parser.add_argument('--warmup',type=int,default=4)
    parser.add_argument('--repeats',type=int,default=16)
    parser.add_argument('--batch',type=int,default=32768)
    parser.add_argument('--layout',choices=['current','predicted','random'])
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((args.inputs/'report.json').read_text())
    schemas,_=schemas_and_modules(['Dot']);schema=schemas['Dot']
    if hashlib.sha256(schema.ptx.encode()).hexdigest()!=manifest['ptx_sha256']:
        raise ValueError('PTX differs from original run')
    m,k,n=manifest['shape'];count=min(args.batch,m*n)
    report=dict(shape=[m,k,n],batch=count,full_result=False,
                description='paired sampled batches; full outputs verified separately by run.py',
                source_full_report=str((args.inputs/'report.json').resolve()),
                kernel_event_caveat='CUDA event interval may include CPU enqueue gaps; use nsys kernel duration',
                PTX_sha256=manifest['ptx_sha256'],warmup=args.warmup,repeats=args.repeats,
                source_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in (Path(__file__),Path(__file__).with_name('bounded.py'))},
                records=[],uploads=[])
    path=args.output/'samples.json'
    for seed in args.seeds:
        loaded={};sessions={}
        try:
            for label in ('current','predicted','random'):
                if args.layout and args.layout!=label:continue
                info=next(row for row in manifest['layouts'] if row['layout']==label
                          and (label!='random' or row['seed']==seed))
                started=time.perf_counter();loaded[label]=load(info,schema,k)
                load_s=time.perf_counter()-started
                buffers,axes=loaded[label]
                sessions[label]=Resident(schema,buffers,count)
                report['uploads'].append(dict(seed=seed,layout=label,binary_load_verify_s=load_s,
                    graph_H2D_s=sessions[label].graph_h2d_s,
                    identity_hash=info['identity_hash'],array_hashes=info['array_hashes']))
            for phase,pair,label in paired_order(seed,args.warmup,args.repeats,list(sessions)):
                start=random.Random((seed<<32)+pair+(0 if phase=='warmup' else 104729)).randrange(m*n-count+1)
                buffers,axes=loaded[label];batch=bind(buffers,axes,start,count,n)
                started=time.perf_counter();stats=sessions[label].run(batch,replays=2)
                execute_wall=time.perf_counter()-started
                expected=array('q',(k*(lane//n+1)*(lane%n+1) for lane in range(start,start+count)))
                if batch.results!=expected:raise AssertionError('Independent CPU oracle mismatch')
                for replay,event in enumerate(stats['kernel_event_s']):
                    report['records'].append(dict(case=f'MatMul-{m}x{k}x{n}',seed=seed,pair=pair,
                        phase=phase,layout=label.title(),mode='binding' if replay==0 else 'resident',
                        start=start,count=count,kernel_event_us=event*1e6,
                        H2D_us=stats['binding_H2D_s']*1e6 if replay==0 else 0,
                        D2H_us=stats['D2H_s']*1e6 if replay==1 else 0,
                        execute_pair_wall_us=execute_wall*1e6,output_sha256=digest(batch.results)))
                path.write_text(json.dumps(report,indent=2)+'\n')
        finally:
            for session in sessions.values():session.close()
    report['summary']=summarize(report['records']);report['complete']=True
    path.write_text(json.dumps(report,indent=2)+'\n')
    print(str(path),flush=True)


if __name__=='__main__':main()
