#!/usr/bin/env python3
"""CPU-only cProfile attribution of graph preparation and physical packing.

Profile times include instrumentation overhead and are not ordinary benchmark
samples. No CUDA session or device context is created.
"""
import argparse
import cProfile
import hashlib
import json
from pathlib import Path
import pstats
import time
from compare_named_layouts import prepare_case, schemas_and_modules, memory_context, write_json


def profile_call(path, fn):
    profiler = cProfile.Profile(timer=time.process_time)
    value = profiler.runcall(fn)
    profiler.dump_stats(str(path))
    stats = pstats.Stats(profiler)
    top = sorted(stats.stats.items(), key=lambda item: item[1][3], reverse=True)[:40]
    rows = [dict(file=key[0], line=key[1], function=key[2], primitive_calls=v[0], calls=v[1],
                 self_seconds=v[2], cumulative_seconds=v[3]) for key,v in top]
    return value, dict(total_seconds=stats.total_tt, top_cumulative=rows,
                       note='Nested cumulative times must not be added; profiler overhead is present')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--shape', default='64x128x64')
    args = p.parse_args()
    shape = tuple(int(n) for n in args.shape.split('x'))
    if len(shape)!=3 or min(shape)<1 or (shape[0]+shape[2])*shape[1]+shape[0]*shape[2]>150000:
        p.error('Require bounded positive MxKxN')
    args.output.mkdir(parents=True, exist_ok=False)
    schemas, modules = schemas_and_modules(['Dot'])
    result = dict(shape=shape, evidence='CPU cProfile; no CUDA', clock='process_time', profiles={})
    with memory_context():
        value, preparation = profile_call(args.output/'preparation.prof', lambda: prepare_case('matmul',shape,schemas,modules,[928,929,930],args.output,2))
        case, pack = value
        result['preparation'] = preparation
        result['case'] = case['id']
        for layout in ('Current','Predicted','Random'):
            _, stats = profile_call(args.output/(layout+'.prof'), lambda: [pack(layout,928) for _ in range(3)])
            result['profiles'][layout] = stats
    result['source_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    write_json(args.output/'cpu-profile.json', result)
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
