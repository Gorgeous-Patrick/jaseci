"""Independently audit full cursor concatenation from Current's actual CSR."""
from array import array
from collections import deque
import json
from pathlib import Path
import sys
from bounded import digest


def main(folder):
    folder=Path(folder);report=json.loads((folder/'report.json').read_text())
    current=next(v for v in report['layouts'] if v['layout']=='current')
    predicted=next(v for v in report['layouts'] if v['layout']=='predicted')
    values=[]
    for info in current['packed_files']:
        data=array(info['type'])
        with Path(info['path']).open('rb') as stream:data.fromfile(stream,info['count'])
        if digest(data)!=info['sha256']:raise ValueError('Current artifact checksum mismatch')
        values.append(data)
    _,tags,offsets,targets,left,right=values
    candidates=[];size=len(tags)
    for channel,seeds in enumerate((left,right)):
        pending=deque(seeds);seen=set(seeds);order=array('q')
        while pending:
            node=pending.popleft();order.append(node)
            row=channel*(size+1)+node
            for target in targets[offsets[row]:offsets[row+1]]:
                if target not in seen:seen.add(target);pending.append(target)
        candidates.append(order)
        with (folder/f'cursor-{channel}-actual-BFS-current-identities.bin').open('wb') as stream:order.tofile(stream)
    expected=candidates[0]+candidates[1]
    actual=array('q')
    with (folder/'predicted-identity-order.bin').open('rb') as stream:actual.fromfile(stream,size)
    if actual!=expected:raise AssertionError('Predicted differs from complete A then complete B BFS')
    if len(set(candidates[0])&set(candidates[1])):raise AssertionError('This MatMul input graph must have disjoint A/B identities')
    audit=dict(shape=report['shape'],cursor_discovered=[len(v) for v in candidates],
               complete_A_then_complete_B=True,identity_count=size,
               current_predicted_identity_equal=current['identity_hash']==predicted['identity_hash'],
               current_predicted_array_equal=[a==b for a,b in zip(current['array_hashes'],predicted['array_hashes'])],
               cursor_candidate_hashes=[digest(v) for v in candidates],
               concatenation_hash=digest(expected),predicted_hash=digest(actual),
               raw_identity_orders=str(folder.resolve()))
    (folder/'identity-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
    print(json.dumps(audit,indent=2))


if __name__=='__main__':main(sys.argv[1])
