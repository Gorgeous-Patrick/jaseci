# Jac GPU Multiple Cursors: Layout Experiments and Evidence Limits

> Historical record (2026-10-06): Predicted in this report uses the rank-interleaved merge that has since been removed,
> rather than the complete per-cursor BFS concatenation that became the default on 2026-10-07. Historical raw data is unchanged;
> the new policy requires independent auditing and measurement, and this report's results cannot be attributed to it.

GPU joint-cursor execution and a prediction packer that performs separate multi-source BFS for each channel across the entire batch have been implemented. The experiments used an actual RTX 3090. Transformer GPU work was stopped during GPU measurements, and the exclusive window was released after measurements and the final CUDA regressions. No changes were committed or pushed, and system configuration was not modified.

**There is a hard gap in GPU causal evidence: ncu 2025.2.1 returned `ERR_NVGPUCTRPERM`; an attempt to elevate only that process with `sudo -n` failed because a password was required. No cache, coalescing, actual memory-transaction, bandwidth, or occupancy counters were obtained, so these mechanisms cannot explain the timing differences.** Both failure logs are retained. No administrator response was awaited, and address contiguity or input size is not treated as hardware evidence.

## Implementation and Correctness

The [syntax, semantics, and GPU subset](gpu-named-cursors.md) describe any compile-time-fixed cursor count, stable current positions and private FIFOs per channel, joint arrival/entry matching, repeated events, and termination conditions. The legacy single-channel chain/CSR path is retained. Dynamic scalar loops, branches, arithmetic, and reports reuse existing lowering. The initial GPU subset supports one joint ability with the same trigger node type and at most one unconditional or simple conditional visit per channel; more general trigger/visit combinations are explicitly rejected. CSR supports bounded branching and cycles; chain mode validates single successors and absence of cycles.

Physical nodes are shared once by identity, with SoA fields; heads, CSR rows, and targets are all remapped. Prediction affects only physical layout and never merges actual arrival events. Conditional visits use conservative relation expansion, and a budget or discovery set guarantees that prediction terminates; execution still follows the actual conditions and FIFOs. The [runnable examples](../../jac/examples/gpu/named_cursors.jac) include same-type two-cursor dot products, three cursors, conditional visits, loops, and integer matmul with shared A-row/B-column inputs. Each input/output Scalar stores only one int. The GPU writes walker.total, and the host publishes output nodes; device-side node writes were not added.

All 12 named-cursor tests in the final working tree passed on actual CUDA, also covering CPU references, LLVM host JIT, and the mock ABI. Coverage includes three/seven cursors, shared nodes, empty/unequal queues, type mismatches, CSR branching/repeated arrivals, conditional visits, no visits, loops, and reports. This evidence is explicitly separate from mock/JIT results. Earlier, the legacy GPU host regression suite ran 92 tests: 90 passed and 2 device-only tests were skipped; both skipped tests subsequently passed with CUDA. The 13 legacy integer/loop CUDA tests and 11 repository PTX/CPU tests also passed. 2 new physical-permutation/summary-boundary tests passed.

## Method and Raw Artifacts

GPU: NVIDIA GeForce RTX 3090, driver 595.71.05; nsys 2025.1.3.140, ncu 2025.2.1.0. The source revision during measurement was `2c130ccbe08aed1725de9693668aaf3d4386977e`, with an uncommitted working tree. Per-file SHA256 hashes and matching source snapshots for key compiler/runtime/measurement code are retained, because commits by other agents mean HEAD alone cannot describe the measured source. Python version, PTX hash, dtype, launch parameters, and GPU telemetry before/after measurement are in inputs.json. GPU clocks were not locked.

[Main inputs and environment](../../dist/gpu-layout-exclusive-20261006/inputs.json),
[ordinary CSV](../../dist/gpu-layout-exclusive-20261006/wall-events.csv),
[raw nsys report](../../dist/gpu-layout-exclusive-20261006/trace.nsys-rep),
[nsys SQLite](../../dist/gpu-layout-exclusive-20261006/trace.sqlite),
[aligned kernel CSV](../../dist/gpu-layout-exclusive-20261006/profile-launches.csv),
[counter failure](../../dist/gpu-layout-exclusive-20261006/ncu-matmul-predicted.log),
and [privilege-elevation failure](../../dist/gpu-layout-exclusive-20261006/ncu-matmul-predicted-privileged.log).
A complete copy is in `dist/gpu-layout-exclusive-20261006/`, including typed input binaries,
CSV/JSON, source snapshots, raw profiler data, CPU `.prof` files, and SHA256 manifests.
The [repository-readable machine report](../../scripts/gpu_walker/validation/named_layouts_3090_profiled.json)
retains per-seed paired statistics, complete distributions, permutation audits, and the environment.

The [runner](../../scripts/gpu_walker/compare_named_layouts.py) reuses the fixed seeds, paired sampling, and strict profiler replay method from the old compare_layouts.py. The old single-channel script also ran successfully, with separate output in `/tmp/jac-legacy-layout-profile/`. The unified runner uses seeds 928/929/930, block=128, 6 warmup rounds and 16 repetitions per seed, and randomized layout order within each pair. Random permutes Current's unified, deduplicated physical indices, consistently remapping every field, channel head, CSR row, and target while preserving within-row order and lane assignment. Every launch checks all lanes against a CPU arithmetic oracle and another layout; selected Jac CPU walker lanes are also run for differential checking. Input weights, dtype, and launch configuration are identical.

```sh
python scripts/gpu_walker/compare_named_layouts.py \
  --chain-cases 128x8 1024x64 --dot-cases 128x8 1024x32 \
  --matmul-cases 16x32x24 32x64x48 64x128x64 \
  --seeds 928 929 930 --warmup 6 --repeats 16 --profile \
  --output /tmp/jac-layout-exclusive
```

This requires the repository .venv, `PYTHONPATH=jac`, and the LLVM shim environment configuration in the README. Explicit CPU/device size limits prevent OOM; the input-node count is `(M+N)*K`, without copying input per product. Ordinary timing and nsys replay run separately. nsys individually checked the names, geometry, and order of 2,541 kernels, aligning every one with its cuLaunchKernel correlation. CUDA event intervals may include host enqueue gaps; the table below reports pure kernel time from a separate nsys/CUPTI run and does not mix it with ordinary timing.

## Are Current and Predicted Actually Different?

The hashes of all measured input arrays were compared individually. The graph was also rebuilt and packed again on the CPU. An audit is accepted only when every rebuilt array's dtype/count/SHA256 for every layout exactly matches the measured data. Identity labels use conservative-discovery indices from the rebuilt graph, not object addresses across processes. The [audit results](../../dist/gpu-layout-exclusive-20261006/identity-audit/layout-identity-audit.json) and complete per-case identity orders are retained.

| Case | Identical identity order | Changed positions | All array hashes identical |
| --- | --- | ---: | --- |
| Dot 128×8 | Yes | 0 | Yes |
| Dot 1024×32 | Yes | 0 | Yes |
| matmul 16×32×24 | No | 1,278 / 1,280 | No |
| matmul 32×64×48 | No | 5,118 / 5,120 | No |
| matmul 64×128×64 | No | 16,128 / 16,384 | No |

Thus, Dot's Current/Predicted timing difference is noise/measurement variation for identical inputs that remains to be explained, **not a layout effect**. Matmul has an actual permutation difference, but explaining GPU time still requires valid counter evidence.

## Measured Kernels and Statistical Variation

The first independent nsys resident-kernel run is reported in μs, as median [p10, p90]. Current is the existing discovery/single-channel-packer order; Predicted applies only to named walkers.

| Case | Current | Predicted | Random, all three seeds combined |
| --- | ---: | ---: | ---: |
| chain 128×8 | 3.200 [3.168,3.232] |  -  | 3.168 [3.104,3.200] |
| chain 1024×64 | 14.431 [14.399,14.432] |  -  | 17.072 [17.023,17.120] |
| Dot 128×8 | 12.960 [12.928,13.023] | 12.959 [12.927,12.992] | 13.567 [13.120,13.792] |
| Dot 1024×32 | 77.198 [47.967,77.534] | 77.294 [48.127,77.822] | 96.782 [69.503,97.886] |
| matmul 16×32×24 | 47.167 [47.071,47.199] | 47.279 [47.071,47.423] | 43.999 [43.679,44.479] |
| matmul 32×64×48 | 92.654 [92.574,92.702] | 93.054 [92.958,93.118] | 97.822 [97.470,98.110] |
| matmul 64×128×64 | 226.955 [184.220,245.115] | 257.994 [186.588,267.642] | 239.403 [199.835,242.139] |

Wide-distribution cases received additional controlled replay with fixed inputs and no graph construction/packing: 16 warmup rounds and 64 repetitions per seed. The [ordinary results](../../dist/gpu-layout-exclusive-20261006/controlled-normal/records.csv), [independent nsys trace](../../dist/gpu-layout-exclusive-20261006/controlled-trace.nsys-rep), and [controlled paired results](../../dist/gpu-layout-exclusive-20261006/controlled-profile/records.csv) are all retained. Controlled nsys paired Random/Predicted ratios are:

| Case | seed 928 median | seed 929 median | seed 930 median | Combined median [p10,p90] |
| --- | ---: | ---: | ---: | ---: |
| Dot 1024×32 | 1.260 | 1.257 | 1.261 | 1.260 [0.940,1.938] |
| matmul 64×128×64 | 0.942 | 1.007 | 0.990 | 0.995 [0.813,1.283] |

A ratio above 1 means Random was slower. Dot's median difference relative to Random is reproducible across the three seeds, but does not mean that the new prediction improves on Current, since their inputs are identical. Matmul ratios span 1 and have wide distributions, so a single median from the first run cannot establish a stable benefit or regression. Faster Random timing for small matmul is a measurement observation whose GPU mechanism remains unexplained. Unsampled dynamic clocks or other factors are not treated as established causes.

## Cost Explanations Supported by Profiling

nsys measured a median short-chain kernel duration of approximately 3.2 μs, while the same case's one-shot cuLaunchKernel API median was approximately 5.81 μs. Total device H2D was approximately 3.78 μs and D2H approximately 1.86 μs. Small differences in pure kernel time therefore do not represent total application cost. API and kernel work can overlap and must not simply be added. For the large shared-input matmul, total device-copy durations were approximately 85.87 μs H2D and 5.28 μs D2H; the cuLaunchKernel API took approximately 7.01 μs. Host APIs include submission/synchronization and other costs, making them longer than pure device copies. Raw API and copy records are in trace-facts.json; these times are not used to infer a device-memory-bandwidth bottleneck.

In ordinary one-shot timing for matmul 64×128×64, Current/Predicted/Random median packing costs were 223.416 / 223.182 / 259.365 ms; pack-through-D2H costs were 224.202 / 223.986 / 260.154 ms. Predicted's median BFS stage was 6.630 ms. Compared with kernels taking hundreds of μs, reconstruction/packing costs dominate the current measured one-shot execution cost; even resident savings of tens of μs would not amortize repacking every time. Variation in whole-run sampling affects the packing difference between layouts, so it cannot establish that BFS is free. Graph build is timed separately, and graph-through-D2H adds that independent measurement as a combined cost, excluding final output-node publication. Session/context initialization is listed separately as setup; steady-state one-shot runs reuse the session.

The [CPU cProfile](../../dist/gpu-layout-exclusive-20261006/cpu-profile/cpu-profile.json) uses the same 64×128×64 graph, with CPU-only execution and three packs per layout. Current pack_cursors totaled 1.984 s, including 0.645 s in nested walk; Predicted predict_layout totaled 0.115 s; Random permute_cursors totaled 0.233 s. This confirms CPU overhead in collection/queries, prediction, and reordering. Profile times include instrumentation overhead and cannot replace ordinary pack timing; nested cumulative times must not be added.

Applicable conclusion: resident differences between independent chains and random permutations are measurable. This range of shared-input matmul cases shows no stable new BFS kernel benefit, and predicting on every pack is not justified solely by possible microsecond savings. This is not evidence that BFS is optimal or necessarily faster. The smallest next step is to reuse a packed resident batch, offer Current/Predicted as selectable policies, and collect transaction/cache/occupancy metrics for the same kernel under temporary ncu permissions before deciding whether to change the merge policy for conflicting shared-node orders. Until counters are available, graph sharing, lane mapping, FIFO divergence, pointer chasing, cache behavior, and compute throughput must not be described as established bottlenecks.

## Modified Files and Validation Entry Points

| File | Purpose |
| --- | --- |
| `jac/jaclang/compiler/backends/native/ptx_walker.jac`, `ptx_csr.jac` | Integrate named-cursor schema/LLVM lowering; preserve legacy dispatch |
| `jac/jaclang/runtime/gpu_cursors.py` | Schema-subset checks, joint FIFO kernel, prediction packer, SoA ABI, and CUDA execution |
| `jac/jaclang/runtime/gpu.jac`, `gpu_cuda.jac` | Schema, packer, memory planning, and session dispatch |
| `jac/examples/gpu/named_cursors.jac` | Dot/Three/conditional visits/loops/reports/shared integer matmul |
| `jac/tests/compiler/backends/native/test_ptx_named_cursors.jac`, `scripts/gpu_walker/test_named_cursors.py` | Compilation, CPU/JIT/mock/actual CUDA correctness, and rejection diagnostics |
| `scripts/gpu_walker/test_integers.py` | Fix temporary module-name collisions to allow combined regression runs |
| `scripts/gpu_walker/compare_named_layouts.py`, `layout_benchmark.py`, `test_layout_benchmark.py` | Strict physical permutations, paired timing, event instrumentation, and boundary tests |
| `profile_named_layout.py`, `replay_layout_timings.py`, `analyze_layout_trace.py`, `profile_layout_cpu.py`, `audit_layout_orders.py` | Separate counters/controlled timing/trace observations/CPU profiling/permutation audits; all under `scripts/gpu_walker/` |
| `docs/design/named-cursors.md`, `gpu-named-cursors.md`, this report; `scripts/gpu_walker/README.md`, `runtime.md` | Syntax, semantics, ABI, execution, and result evidence |
| `scripts/gpu_walker/validation/named_cursors_3090.json`, `named_layouts_3090_profiled.json` | Preliminary correctness records and the complete machine-readable report for formal measurements |

The actual CUDA final-regression log, [jac-named-exclusive-cuda.log](../../dist/gpu-layout-exclusive-20261006/jac-named-exclusive-cuda.log), and CPU regression log, [jac-named-final-host.log](../../dist/gpu-layout-exclusive-20261006/jac-named-final-host.log), are retained with the experiment artifacts. Python compilation checks and `git diff --check` passed. This task did not rewrite shared-directory Transformer/slides/littleX/pycore files, data files, or the stash. Independent source hashes and snapshots distinguish this work from other agents' commits/changes.
