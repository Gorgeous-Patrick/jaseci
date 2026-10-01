# GPU walker state fields: correctness validation

Validated on 2026-10-01 using clarity2's NVIDIA GeForce RTX 3090, driver
560.35.05, and Python 3.13.7. Tests used an isolated checkout with the LLVM
NVPTX shim; the original server checkout remained unchanged. Device memory
returned to its initial 67 MiB after cleanup.

| Check | Result |
| --- | --- |
| Multi-state suite plus the 1,000-walker example | 9 tests passed; 97 real CUDA launches |
| Integer single-state compatibility suite | 6 tests passed; 33 real CUDA launches |
| Related local Jac regression checks | All 21 covered checks passed after the fixture update below |
| `jac precommit --verify` on changed Jac files | 9 files passed |

The local regression run initially passed 20 checks and failed one obsolete
negative fixture: it expected two assignments in a branch to be rejected.
Sequential updates are now supported. The fixture now verifies that
`total += 1; total *= 2;` turns 3 into 8 in the taken branch, while retaining
rejections for unsupported effects. The affected check passed on a targeted
rerun, and its six-test integer suite also passed on real CUDA. No production
code change was needed after the successful multi-state device tests.

The device tests cover chain and CSR traversal, int64 and float64 state,
flat and nested state, four and six leaf fields, and batches of
1/2/31/32/33/257/1000 walkers. They compare every successful output field
with ordinary serial Jac, including sequential cross-field reads, branches,
FIFO repeated arrivals, and untouched fields. Expected overflow and modulo
errors leave every result slot in the failing lane unchanged and prevent all
host publication. Host-only driver tests cover allocation reuse, alias/type
rejection, changed host state, empty traversals, and cleanup after driver faults.

The example checks `total`, `count`, `metrics.weighted`, and `metrics.last`
for all 1,000 walkers. Its first five totals are `[3, 3, 5, 6, 6]`.
Node and walker leaves must still share one numeric type; nested mutable
walker objects must have exclusive ownership. This is correctness validation,
not a throughput benchmark. Test duration includes compilation and serial
reference execution; kernel performance was not measured.

Run from a checkout with a working Jac/CUDA environment:

```bash
jac run jac/examples/gpu/walker_fields_run.jac
PYTHONPATH=jac JAC_GPU_TEST_CUDA=1 python3 -B scripts/gpu_walker/test_state_fields.py -v
PYTHONPATH=jac JAC_GPU_TEST_CUDA=1 python3 -B scripts/gpu_walker/test_integers.py -v
jac test jac/tests/runtimelib/test_gpu.jac jac/tests/compiler/backends/native/test_ptx_walker.jac jac/tests/compiler/backends/native/test_ptx.jac
```

Full validation records, source hashes, logs, and the exact loaded PTX are
retained in the GPU workspace's `artifacts/gpu-walker-fields/` directory.
The harness verifies source hashes before and after execution and counts only
launches made through the real CUDA shared library as device launches.
