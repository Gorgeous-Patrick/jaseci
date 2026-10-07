#!/usr/bin/env python3
"""CPU reconstruction audit of recorded inputs and deterministic identity order.

Identity labels are conservative-discovery indices in a freshly rebuilt graph,
not process addresses. Reconstruction is accepted only if every recorded packed
array matches exactly (dtype/count/SHA256), including heads and ordered CSR.
"""
import argparse
import json
from pathlib import Path
from compare_named_layouts import prepare_case, schemas_and_modules, memory_context, write_json


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((args.input/'inputs.json').read_text())
    schemas,modules=schemas_and_modules()
    audits=[]
    for original in manifest['cases']:
        with memory_context():
            rebuilt,_=prepare_case(original['kind'],tuple(original['shape']),schemas,modules,
                                  manifest['seeds'],args.output,manifest['queue_capacity'])
            infos={x['label']:x for x in rebuilt['layouts']}
            for saved in original['layouts']:
                new=infos[saved['label']]
                if len(new['files'])!=len(saved['files']) or any(
                    any(a[k]!=b[k] for k in ('sha256','type','count'))
                    for a,b in zip(new['files'],saved['files'])):
                    raise AssertionError('Reconstructed input differs: '+original['id']+'/'+saved['label'])
            cur=infos['Current'];pred=infos.get('Predicted')
            audit=dict(case=original['id'], reconstruction_all_arrays_match=True,
                       identity_label='conservative discovery index; reconstructed, not runtime address')
            if pred:
                a,b=cur['identity_order'],pred['identity_order']
                audit.update(identity_order_identical=a==b,
                    current_identity_order_sha256=cur['identity_order_sha256'],
                    predicted_identity_order_sha256=pred['identity_order_sha256'],
                    identity_positions_changed=sum(x!=y for x,y in zip(a,b)),
                    array_hashes_identical=all(x['sha256']==y['sha256'] for x,y in zip(cur['files'],pred['files'])),
                    differing_array_indices=[i for i,(x,y) in enumerate(zip(cur['files'],pred['files'])) if x['sha256']!=y['sha256']],
                    current_order_prefix=a[:32],predicted_order_prefix=b[:32])
            write_json(args.output/(original['id']+'-reconstructed.json'),rebuilt)
            audits.append(audit)
    write_json(args.output/'layout-identity-audit.json',dict(evidence='CPU deterministic reconstruction with exact measured-array checksums',cases=audits))
    print(json.dumps(audits,indent=2))


if __name__=='__main__':main()
