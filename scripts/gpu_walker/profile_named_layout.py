#!/usr/bin/env python3
"""Replay one recorded physical layout for separate Nsight Compute capture.

Use ncu --launch-skip 5 --launch-count 1 with the default four warmups.
The initial upload/verification and warmup kernels are deliberately excluded.
"""
import argparse
import hashlib
import json
from pathlib import Path
from compare_named_layouts import load_array, load_layout, schemas_and_modules
from layout_benchmark import MeasuredSession


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--case', required=True)
    parser.add_argument('--layout', required=True)
    parser.add_argument('--warmup', type=int, default=4)
    args = parser.parse_args()
    if args.warmup < 0:
        parser.error('warmup must be nonnegative')
    manifest = json.loads((args.input / 'inputs.json').read_text())
    case = next(c for c in manifest['cases'] if c['id'] == args.case)
    info = next(i for i in case['layouts'] if i['label'] == args.layout)
    schemas, _ = schemas_and_modules([case['source_key']])
    schema = schemas[case['source_key']]
    if hashlib.sha256(schema.ptx.encode()).hexdigest() != manifest['sources'][case['source_key']]['ptx_sha256']:
        raise ValueError('PTX differs from recorded benchmark')
    session = MeasuredSession(schema, load_layout(info, schema), list(load_array(case['expected'])),
                              manifest['block_size'], manifest['device'])
    try:
        session.execute()
        for _ in range(args.warmup):
            session.resident()
        result = session.resident()
        print(json.dumps(dict(case=args.case, layout=args.layout, correctness='PASS',
                              profiling_only=True, metrics=result)))
    finally:
        session.close()


if __name__ == '__main__':
    main()
