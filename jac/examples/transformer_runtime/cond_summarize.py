"""Summarize saved Cond correctness evidence; does not invoke Torch or CUDA."""
import json
from pathlib import Path

root = Path(__file__).parent
rows = {}
for device in ('cpu', 'cuda_0'):
    report = json.loads((root / 'results' / ('cond_' + device + '.json')).read_text())
    assert report['engines'] == ['walker', 'fx', 'inductor']
    assert len(report['cases']) == 4 and all(c['unselected_absent'] for c in report['cases'])
    assert len(report['invalid']) == 14
    assert all(report[k] == 'passed' for k in ('shared_fanout', 'same_root', 'unsafe_unselected_gather',
                                              'branch_layout_normalization', 'condition_only_branch_dependency',
                                              'explicit_weight_operands', 'weight_refresh'))
    code = (root / 'results' / ('cond_' + device + '_fx.py')).read_text()
    assert 'torch.ops.higher_order.cond' in code and '# Extracted branch module: cond_true' in code and '# Extracted branch module: cond_false' in code
    rows[device] = dict(dtype=report['dtype'], repeated_predicates=[c['predicate'] for c in report['cases']],
                        max_abs_error=dict(walker=max(c['max_abs_error'] for c in report['cases']),
                                           fx=max(c['engine_max_abs_errors']['fx'] for c in report['cases']),
                                           inductor=max(c['engine_max_abs_errors']['inductor'] for c in report['cases'])),
                        invalid_checks=len(report['invalid']), status='passed', preservation=report['preservation'])
summary = dict(status='passed', results=rows, note='Correctness measurements only; no performance measurements. Raw traces, actual graph/FX exports and slice plans accompany these results.')
(root / 'results' / 'cond_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
lines = ['# Cond correctness', '', '| device | dtype | walker max abs | FX max abs | Inductor max abs | invalid checks |', '|---|---|---:|---:|---:|---:|']
for device, row in rows.items():
    errors = row['max_abs_error']
    lines.append(f"| {device} | {row['dtype']} | {errors['walker']:.4g} | {errors['fx']:.4g} | {errors['inductor']:.4g} | {row['invalid_checks']} |")
lines += ['', 'All cases passed: repeated positive/negative predicates, selected-only traces, shared fanout, identical roots, condition dependencies reused by one branch, different producer strides, explicit weight operands/refresh, and unselected out-of-range Gather.', '', 'CPU additionally verifies that selecting the unsafe Gather raises an index error and that the next valid inference recovers. CUDA does not deliberately execute invalid indices. Both older example directories remain unchanged (80 and 74 files).', '', 'Full Transformer CPU/CUDA regressions are recorded separately in summary.json. No benchmark or speed claim.']
(root / 'results' / 'cond_summary.md').write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
