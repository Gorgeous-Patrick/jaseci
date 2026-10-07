#!/usr/bin/env python3
"""CPU audit of actual packed matmul identities, physical indices and hashes.

Labels are recovered by following the recorded Current CSR rows from lane heads;
no matmul coordinate influences the production packer. Predicted indices come
from its exact identity permutation, not equal-valued field guesses.
"""
import argparse
import hashlib
from pathlib import Path
from compare_named_layouts import (load_layout, memory_context, prepare_case,
                                  schemas_and_modules, write_json)


def audit_case(shape, schemas, modules, output):
    m, k, n = shape
    case, _ = prepare_case('matmul', shape, schemas, modules, [928, 929, 930], output, 2)
    layouts = {info['label']: info for info in case['layouts']}
    current = load_layout(layouts['Current'], schemas['Dot'])
    nodes, lanes = len(current.tags), m*n
    labels = {}
    for channel, count in ((0, m), (1, n)):
        for line in range(count):
            lane = line*n if channel == 0 else line
            slot = current.heads[channel*lanes+lane]
            for step in range(k):
                label = f'A[{line},{step}]' if channel == 0 else f'B[{step},{line}]'
                if slot in labels and labels[slot] != label:
                    raise AssertionError('Unexpected cross-input alias')
                labels[slot] = label
                row = channel*(nodes+1)+slot
                successors = current.targets[current.offsets[row]:current.offsets[row+1]]
                if len(successors) != int(step < k-1):
                    raise AssertionError('Input is not the expected ordered chain')
                if successors:
                    slot = successors[0]
    if len(labels)!=nodes:
        raise AssertionError('Packed identity coverage mismatch')
    orders = {}
    for name in ('Current','Predicted'):
        info = layouts[name]
        buffers = load_layout(info, schemas['Dot'])
        order = info['identity_order']
        orders[name] = [dict(physical_index=i, discovery_identity=old,
                            label=labels[old], projected_values=[column[i] for column in buffers.columns()])
                        for i,old in enumerate(order)]
    expected = [f'A[{i},{q}]' for q in range(k) for i in range(m)] + [f'B[{q},{j}]' for q in range(k) for j in range(n)]
    actual = [row['label'] for row in orders['Predicted']]
    if actual != expected:
        raise AssertionError('Predicted is not complete batch A BFS then complete batch B BFS')
    result = dict(case=case['id'],shape=shape,correctness='PASS',
                  strategy=layouts['Predicted']['prediction_strategy'],
                  expected_predicted_labels=expected,actual_orders=orders,inputs=case,
                  current_predicted_identity_identical=layouts['Current']['identity_order']==layouts['Predicted']['identity_order'],
                  current_predicted_arrays_identical=all(a['sha256']==b['sha256'] for a,b in zip(layouts['Current']['files'],layouts['Predicted']['files'])))
    write_json(output/(case['id']+'-identity-audit.json'),result)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--cases',nargs='+',default=['4x4x4','3x5x2'])
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    shapes=[tuple(int(v) for v in s.split('x')) for s in args.cases]
    if any(len(s)!=3 or min(s)<1 or (s[0]+s[2])*s[1]>10000 for s in shapes):
        p.error('Require positive bounded MxKxN')
    schemas,modules=schemas_and_modules(['Dot'])
    results=[]
    for shape in shapes:
        with memory_context():
            results.append(audit_case(shape,schemas,modules,args.output))
    write_json(args.output/'audits.json',results)
    write_json(args.output/'inputs.json',dict(cases=[r['inputs'] for r in results],
        block_size=128,device=0,seeds=[928,929,930],warmup=6,repeats=16,
        sources={key:dict(ptx_sha256=hashlib.sha256(schema.ptx.encode()).hexdigest())
                 for key,schema in schemas.items()}))
    for result in results:
        print(result['case'], 'PASS', [r['label'] for r in result['actual_orders']['Predicted']])


if __name__=='__main__': main()
