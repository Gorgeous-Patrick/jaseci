"""Summarize saved correctness evidence and verify preserved examples; no GPU use."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'preservation.json').read_text())
for folder, expected in manifest.items():
    base=ROOT.parent/folder
    actual={str(path.relative_to(base)):hashlib.sha256(path.read_bytes()).hexdigest()
            for path in base.rglob('*') if path.is_file()}
    assert actual==expected, f'Preserved files changed: {folder}'

summary={'status':'passed','preserved_files':{folder:len(entries) for folder,entries in manifest.items()},'cases':[]}
lines=['| device | config / dtype | walker / FX vs reference max abs | Inductor vs reference max abs |',
       '|---|---|---:|---:|']
for device in ('cpu','cuda_0'):
    data=json.loads((ROOT/'results'/('validation_'+device+'.json')).read_text())
    assert data['status']=='passed' and data['library_reuse']['status']=='passed'
    assert len(data['invalid_dependencies'])==19
    for label,case in data['cases'].items():
        assert case['status']=='passed' and case['compiled']['status']=='passed'
        row=dict(device=device,config_dtype=label,reference_error=case['max_reference_error'],
                 fx_reference_error=case['max_fx_intermediate_error'],
                 inductor_reference_error=case['compiled']['max_intermediate_error'],
                 cpu_device_error=case['max_cpu_device_error'],
                 rewired_inductor=case['rewired_compiled']['status'])
        summary['cases'].append(row)
        lines.append(f"| {device} | {label} | {row['reference_error']:.5g} | {row['inductor_reference_error']:.5g} |")
(ROOT/'results'/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(ROOT/'results'/'summary.md').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
print('PASS: previous examples unchanged:',summary['preserved_files'])
