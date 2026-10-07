#!/usr/bin/env python3
"""Controlled checksum-verified replay without CPU graph building or packing.

Only resident records are summarized. One-shot records retain saved host pack
numbers for ABI compatibility and MUST NOT be treated as new pack measurements.
"""
import argparse
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
from compare_named_layouts import run_case, schemas_and_modules, write_json, write_csv, telemetry
from layout_benchmark import attach_profile, summarize


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--cases', nargs='+', required=True)
    p.add_argument('--warmup', type=int, default=16)
    p.add_argument('--repeats', type=int, default=64)
    p.add_argument('--trace', type=Path)
    args = p.parse_args()
    manifest = json.loads((args.input / 'inputs.json').read_text())
    cases = [c for c in manifest['cases'] if c['id'] in args.cases]
    if len(cases) != len(args.cases):
        p.error('Unknown or duplicate case')
    args.output.mkdir(parents=True, exist_ok=True)
    if args.trace:
        records = json.loads((args.output / 'records.json').read_text())['records']
        geometries = {c['id']: [c['kernel'], (c['walkers']+manifest['block_size']-1)//manifest['block_size'], 1, 1, manifest['block_size'], 1, 1] for c in cases}
        attach_profile(args.trace, records, geometries)
    else:
        schemas, _ = schemas_and_modules()
        for key, schema in schemas.items():
            if hashlib.sha256(schema.ptx.encode()).hexdigest() != manifest['sources'][key]['ptx_sha256']:
                raise ValueError('PTX differs from input snapshot')
        config = SimpleNamespace(seeds=manifest['seeds'], warmup=args.warmup, repeats=args.repeats,
                                 block_size=manifest['block_size'], device=manifest['device'])
        before = telemetry()
        records = [record for case in cases for record in run_case(case, schemas, config)]
        write_json(args.output / 'environment.json', dict(before=before, after=telemetry(),
                   input=str(args.input), warmup=args.warmup, repeats=args.repeats,
                   warning='One-shot host pack costs are replayed metadata, not measured in this run'))
    write_json(args.output / 'records.json', dict(records=records))
    write_csv(args.output / 'records.csv', records)
    summary = summarize([r for r in records if r['mode']=='resident'])
    write_json(args.output / 'resident-summary.json', summary)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
