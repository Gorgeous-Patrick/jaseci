#!/usr/bin/env python3
"""THEORETICAL address model: distinct 32-byte sectors per logical warp load.

Not hardware transactions, requests, cache misses, DRAM traffic or profiling.
Models exact packed SoA/CSR addresses for unconditional single-successor Dot;
compiler CSE/vectorization/predication and hardware cache reuse are not modeled.
Different cursor/load/warp/round events are never combined into one request.
"""
import argparse
from collections import defaultdict
from pathlib import Path
import json
from compare_named_layouts import load_layout, schemas_and_modules, write_json
from compare_layouts import distribution


def analyze(buffers, case):
    if buffers.cursor_spec.conditional or any(x>1 for x in buffers.seed_counts):
        raise ValueError('Only unconditional single-seed chains are modeled')
    n, lanes = len(buffers.tags), len(buffers.status)
    channels = len(buffers.cursor_spec.cursor_names)
    plan = buffers.memory_plan()
    starts = plan.graph_layout.offsets
    f = len(buffers.columns())
    groups = defaultdict(list)
    first_warp = []
    current = [list(buffers.heads[ch*lanes:(ch+1)*lanes]) for ch in range(channels)]
    rounds = 0
    while any(all(current[ch][lane]>=0 for ch in range(channels)) for lane in range(lanes)):
        if rounds > 100000:
            raise ValueError('Bounded finite chain analysis only')
        next_current = [[-1]*lanes for _ in range(channels)]
        for warp in range((lanes+31)//32):
            active = [lane for lane in range(warp*32,min(lanes,(warp+1)*32)) if all(current[ch][lane]>=0 for ch in range(channels))]
            for ch in range(channels):
                ids = [current[ch][lane] for lane in active]
                if not ids:
                    continue
                loads = {}
                for col in range(f):
                    loads[f'node_value.column_{col}.cursor_{ch}'] = [starts[col]+node*8 for node in ids]
                loads[f'tag.cursor_{ch}'] = [starts[f]+node*8 for node in ids]
                rows = [ch*(n+1)+node for node in ids]
                loads[f'csr_begin.cursor_{ch}'] = [starts[f+1]+row*8 for row in rows]
                loads[f'csr_end.cursor_{ch}'] = [starts[f+1]+(row+1)*8 for row in rows]
                targets = []
                for lane,row in zip(active,rows):
                    begin,end = buffers.offsets[row:row+2]
                    if end-begin>1:
                        raise ValueError('Model requires at most one successor')
                    if end>begin:
                        targets.append(starts[f+2]+begin*8)
                        next_current[ch][lane] = buffers.targets[begin]
                if targets:
                    loads[f'csr_target.cursor_{ch}'] = targets
                for name,addresses in loads.items():
                    sectors = sorted({byte//32 for address in addresses for byte in (address,address+7)})
                    groups[name].append(len(sectors))
                    if warp==0 and rounds<2:
                        first_warp.append(dict(round=rounds,warp=warp,load=name,
                            logical_addresses=addresses,sector_ids=sectors,
                            theoretical_distinct_32byte_sectors=len(sectors)))
        current = next_current
        rounds += 1
    return dict(case=case['id'],rounds=rounds,evidence='THEORETICAL ADDRESS MODEL ONLY',
                assumed_arena_base_alignment=256,scalar_bytes=8,warp_lanes=32,
                limitations='No executed instruction/request count, cache state or DRAM prediction; logical LLVM loads before backend optimization',
                per_logical_load={key:distribution(values) for key,values in groups.items()},
                first_warp_first_two_rounds=first_warp)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    args=p.parse_args()
    manifest=json.loads((args.input/'inputs.json').read_text())
    schemas,_=schemas_and_modules(['Dot'])
    rows=[]
    for case in manifest['cases']:
        if case['source_key']!='Dot':continue
        for info in case['layouts']:
            data=analyze(load_layout(info,schemas['Dot']),case)
            data.update(layout=info['label'],identity_order_sha256=info['identity_order_sha256'],
                        input_hashes=[f['sha256'] for f in info['files']])
            rows.append(data)
    write_json(args.input/'theoretical-sectors.json',dict(evidence='NOT HARDWARE COUNTERS',results=rows))
    print('Saved theoretical-sectors.json; not actual transactions or DRAM traffic')


if __name__=='__main__':main()
