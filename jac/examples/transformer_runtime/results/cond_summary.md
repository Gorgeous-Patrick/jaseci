# Cond correctness

| device | dtype | walker max abs | FX max abs | Inductor max abs | invalid checks |
|---|---|---:|---:|---:|---:|
| cpu | float64 | 0 | 0 | 0 | 14 |
| cuda_0 | float64 | 0 | 0 | 0 | 14 |

All cases passed: repeated positive/negative predicates, selected-only traces, shared fanout, identical roots, condition dependencies reused by one branch, different producer strides, explicit weight operands/refresh, and unselected out-of-range Gather.

CPU additionally verifies that selecting the unsafe Gather raises an index error and that the next valid inference recovers. CUDA does not deliberately execute invalid indices. Both older example directories remain unchanged (80 and 74 files).

Full Transformer CPU/CUDA regressions are recorded separately in summary.json. No benchmark or speed claim.
