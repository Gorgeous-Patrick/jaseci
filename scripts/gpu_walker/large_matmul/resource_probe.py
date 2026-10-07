"""Bounded CPU-only real Jac graph resource pilot; never creates a CUDA context."""
import argparse
import json
import os
from pathlib import Path
import resource
import time
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from compare_named_layouts import schemas_and_modules, memory_context


def memory():
    values={}
    for line in Path('/proc/self/status').read_text().splitlines():
        if line.startswith(('VmRSS:','VmHWM:')):
            key,value,_=line.split();values[key[:-1]+'_bytes']=int(value)*1024
    return values


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--shape',required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();m,k,n=map(int,args.shape.split('x'))
    if min(m,k,n)<1 or (m+n)*k+m*n>150000:
        p.error('Pilot bound: positive dimensions and at most 150000 input/output nodes')
    schemas,modules=schemas_and_modules(['Dot']);mod=modules['Dot']
    from jaclang.runtime import gpu_cursors
    result=dict(shape=[m,k,n],CPU_only=True,input_nodes=(m+n)*k,
                edges=(m+n)*(k-1),walkers=m*n,output_nodes=m*n,stages=[])
    with memory_context():
        result['stages'].append(dict(stage='baseline',**memory()))
        start=time.perf_counter()
        a=[[((i+q)%7)-3 for q in range(k)] for i in range(m)]
        b=[[((q*3+j)%11)-5 for j in range(n)] for q in range(k)]
        result['stages'].append(dict(stage='dense_weights',wall_s=time.perf_counter()-start,**memory()))
        start=time.perf_counter();walkers,heads,outputs=mod.build_matmul(a,b)
        result['stages'].append(dict(stage='real_Jac_graph',wall_s=time.perf_counter()-start,**memory()))
        start=time.perf_counter()
        batch=gpu_cursors.pack_cursors(schemas['Dot'],walkers,heads,queue_capacity=1,
                max_visits=k+1,layout='predicted',max_nodes=150000)
        result['stages'].append(dict(stage='packed',wall_s=time.perf_counter()-start,
                array_payload_bytes=batch.memory_plan().payload_bytes(),
                arrays=[dict(type=a.typecode,count=len(a),bytes=len(a)*a.itemsize) for a in batch.buffers.arrays()],**memory()))
        result['prediction_strategy']=batch.buffers.prediction['strategy']
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
