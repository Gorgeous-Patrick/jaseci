#!/usr/bin/env python3
"""Extract CUDA copy/launch facts from a separately recorded Nsight trace."""
import argparse
import json
import sqlite3
from pathlib import Path
from layout_benchmark import summarize


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder', type=Path)
    args = p.parse_args()
    records = json.loads((args.folder / 'profile-launches.json').read_text())['records']
    with sqlite3.connect(args.folder / 'trace.sqlite') as db:
        kernels = db.execute('SELECT start,end,contextId,correlationId FROM CUPTI_ACTIVITY_KIND_KERNEL ORDER BY start').fetchall()
        copies = db.execute('SELECT start,end,contextId,bytes,copyKind FROM CUPTI_ACTIVITY_KIND_MEMCPY ORDER BY start').fetchall()
        api_tables = db.execute("SELECT name FROM sqlite_master WHERE name IN ('CUPTI_ACTIVITY_KIND_DRIVER','CUPTI_ACTIVITY_KIND_RUNTIME')").fetchall()
        apis = {}
        api_summary = []
        for (table,) in api_tables:
            apis.update({row[0]: row[1:] for row in db.execute(
                f'SELECT r.correlationId,r.start,r.end,s.value FROM {table} r JOIN StringIds s ON r.nameId=s.id')})
            api_summary.extend(dict(table=table, name=row[0], calls=row[1], mean_us=row[2])
                for row in db.execute(f'SELECT s.value,count(*),avg(r.end-r.start)/1000.0 FROM {table} r JOIN StringIds s ON r.nameId=s.id GROUP BY s.value'))
    if len(records) != len(kernels):
        raise ValueError('Kernel count does not match independently verified launch records')
    for i, (record, kernel) in enumerate(zip(records, kernels)):
        start, end, context, correlation = kernel
        api = apis.get(correlation)
        if api is not None and api[2] == 'cuLaunchKernel':
            record['launch_api_us'] = (api[1]-api[0])/1000
            record['kernel_start_after_api_start_us'] = (start-api[0])/1000
        before = kernels[i-1][1] if i else 0
        after = kernels[i+1][0] if i+1 < len(kernels) else 2**63-1
        for label, kind, lower, upper in [('H2D',1,before,start), ('D2H',2,end,after)]:
            selected = [c for c in copies if c[2] == context and c[4] == kind and c[0] >= lower and c[1] <= upper]
            record[label+'_device_us'] = sum(c[1]-c[0] for c in selected)/1000
            record[label+'_device_bytes'] = sum(c[3] for c in selected)
    result = dict(evidence='Nsight CUPTI device copies and verified kernel launches',
                  note='Resident H2D includes deliberate output poisoning, not graph re-upload; host API costs remain in wall-events.json',
                  cuda_api_tables=[t[0] for t in api_tables], cuda_api_summary=api_summary, records=records,
                  kernel_summary=summarize(records))
    (args.folder / 'trace-facts.json').write_text(json.dumps(result, indent=2)+'\n')
    print('Saved', args.folder / 'trace-facts.json')


if __name__ == '__main__':
    main()
