"""Attach exact ordered Nsight kernel intervals to separately replayed samples."""
import argparse
import json
from pathlib import Path
import sqlite3
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from layout_benchmark import summarize


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples',type=Path,required=True)
    parser.add_argument('--sqlite',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();data=json.loads(args.samples.read_text())
    with sqlite3.connect(args.sqlite) as db:
        kernels=db.execute('''SELECT k.end-k.start,s.value,k.gridX,k.blockX
                             FROM CUPTI_ACTIVITY_KIND_KERNEL k
                             JOIN StringIds s ON k.shortName=s.id ORDER BY k.start''').fetchall()
        if len(kernels)!=len(data['records']):raise ValueError('Kernel/sample count mismatch')
        for record,row in zip(data['records'],kernels):
            if row[1]!='jac_Dot_cursors_batch' or row[2]!=(record['count']+127)//128 or row[3]!=128:
                raise ValueError(f'Kernel or launch geometry mismatch: {row}')
            record['kernel_profiler_us']=row[0]/1000
        data['copy_summary']=db.execute('''SELECT copyKind,COUNT(*),SUM(bytes),SUM(end-start)/1e9
                                           FROM CUPTI_ACTIVITY_KIND_MEMCPY GROUP BY copyKind''').fetchall()
        tables={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        api_table='CUPTI_ACTIVITY_KIND_DRIVER' if 'CUPTI_ACTIVITY_KIND_DRIVER' in tables else 'CUPTI_ACTIVITY_KIND_RUNTIME'
        data['api_table']=api_table
        data['api_summary']=db.execute(f'''SELECT s.value,COUNT(*),SUM(r.end-r.start)/1e9
                                          FROM {api_table} r JOIN StringIds s
                                          ON r.nameId=s.id GROUP BY s.value''').fetchall()
    data['summary']=summarize(data['records'])
    data['raw_profile_sqlite']=str(args.sqlite.resolve())
    args.output.write_text(json.dumps(data,indent=2)+'\n')


if __name__=='__main__':main()
