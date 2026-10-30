# Jac GPU 3000³ MatMul: Full Execution and Layout Comparison

2026-10-07, based on source revision `145f9899fce2e3d08c207721beac0f0aac88a706`.
The previously committed report is unchanged. This round adds only an experiment runner, tests, documentation, and machine-readable summaries; these changes were not committed or pushed.

**The complete 3000×3000×3000 result was actually computed.** All five instances—Current, full cursor BFS Predicted, and Random with seeds 928/929/930—computed all **9,000,000 outputs** and **27,000,000,000 multiply-accumulates**. Every output was verified, and all status values were zero. These results were not extrapolated from smaller sizes, and dense address arrays were not substituted for the Jac Graph.

**Hardware-counter evidence is still missing.** Actual kernel collection with ncu returned `ERR_NVGPUCTRPERM`, and the tool exited with code 1. No password was requested, and permissions and drivers were not changed. Consequently, no causal attribution is made to coalescing, sector/request counts, cache behavior, DRAM, occupancy, or GPU bottlenecks.

## Real Graph, Bounded Execution, and Resources

The experiment uses Scalar, RowNext, ColumnNext, and the Dot ability from the original `named_cursors.jac`. The real, shared input graph was built once: 18,000,000 Scalar nodes and 17,994,000 edges. Each node stores only one int. Inputs are not copied per product. Each layout's read-only SoA/CSR occupies approximately 719,952,016 bytes (0.671 GiB), uploaded once and reused across all output batches.

Each batch has at most 32768 independent GPU walker lanes. A total of 275 launches covers every output; the last batch has 21632 lanes. Private state occupies approximately 2.13 MiB per full batch, without creating nine million CPU walker objects simultaneously. Within each bounded batch, every result is materialized as a real Scalar output node holding one int, saved to an int64 binary, and released; **the complete graph of nine million CPU output nodes is not retained simultaneously**.

Queue capacity=1: there is one initial seed, and each round consumes an arrival before appending at most one successor, so pending≤1. The actual CSR was checked for outdegree≤1 for each relation; the constructed chains have length K=3000, with max_visits=3001. This proof applies only to this fixture and does not change the rules for general branching CSR queues.

The weights are A[i,k]=i+1 and B[k,j]=j+1. The independent CPU oracle for each output is K*(i+1)*(j+1), using int64; every complete output was checked individually. Each instance's result file is 72,000,000 bytes, with the same SHA256:
`4e4078629f40c5b0bf4fcea300c74af4fcdacad32b440945343a1716986840de`.

Reversible small-scale trials were run first: the real graph with 96k input nodes took 1.01s, and the real graph with 768k input nodes took 4.64s; peak RSS in the small trials was 1.33 GiB. Full-graph construction measured **140.80s, with RSS of 17.32 GiB at completion**; recorded peak RSS for the full run was **27.78 GiB**. The host has 78 GiB RAM, initially with 72 GiB available; cgroup memory.max=max, with 2 GiB swap. Guards required RSS≤48 GiB and available RAM≥20 GiB; neither guard was triggered. The production packer's default OOM limits were not changed.

## Actual Permutation Audit

Predicted explicitly uses prediction_budget=9,000,000. Each of the two cursors expanded/discovered 9,000,000 identities, with truncated=false. The compressed set of 5999 planning bindings covers all columns of the first row, followed by the first column of every remaining row; first-seed order matches the complete row-major lane order. Only layout discovery is compressed; actual outputs and arrival events are not. Regression tests compare actual node identity order and all read-only arrays for 4×4×4, 3×5×2, and single-row/single-column boundary cases, and differentially compare all batched LLVM JIT outputs against actual CPU Jac spawn execution.

An independent audit reconstructs the complete multi-source BFS for both channels from Current's actual CSR and heads. The Predicted identity array equals **the complete A sequence followed by the complete B sequence**, element by element, for 18m identities. The A and B sets are disjoint here.

- Current and Predicted have **different identity orders**.
- The value, CSR offset, and target hashes differ; the tag hash is identical because all nodes are Scalar.
- The independent concatenation and Predicted share the identity SHA256:
  `6f0291591238c28e0671cca567bfd39db70f89795ea07760325d91bbee7c72fa`.
- All raw orders, A/B candidate orders, and field arrays are retained as binaries rather than per-node JSON.
- Random permutes the unified physical indices and consistently remaps every field, CSR row/target, and head/queue. Within-row neighbor order and walker/lane order are preserved. All three seeds were fully verified.

The [machine-readable audit](../../scripts/gpu_walker/large_matmul/validation/identity-audit.json) contains the complete hashes; see also the [raw audit](/tmp/jac-large-matmul-3000-20261007/identity-audit.json).

## Formal Performance Sampling: A Subset on the Full Graph

These timings are separate from the full-result verification above. They reuse the exact checksummed packed binaries, with identical int64 data, PTX, 32768 lanes, 128 threads/block (256 blocks), inputs, and bindings. Each seed uses 4 warmup rounds and 16 measured paired rounds, with layout order shuffled using the fixed seed. Each pair uses the same output starting point: the first launch uploads bindings, and the second replays them resident. Every result is still checked against the CPU oracle. **Each layout has 48 measured resident samples, each covering only 32768 outputs; these samples must not be treated as timings for all nine million outputs.**

Ordinary event timing and nsys replay ran in two separate processes, both exiting normally with code 0. The earlier experimental process and its GPU context had exited before sampling began, and there were no other GPU compute processes. This task's regressions, graph construction, and analysis did not run concurrently. Another user's idle resource_tracker process consumed no CPU and was left untouched.

| Method (n=48 per layout) | Current min / median / max ms | Predicted min / median / max ms | Random min / median / max ms |
| --- | --- | --- | --- |
| Ordinary CUDA event | 8.826 / 8.907 / 8.996 | 8.835 / 8.879 / 8.952 | 70.179 / 70.319 / 70.429 |
| nsys pure kernel duration | 8.795 / 8.851 / 8.959 | 8.917 / 8.973 / 9.041 | 70.665 / 70.802 / 70.961 |

A CUDA event interval can include CPU enqueue gaps; the nsys pure kernel duration is used for kernel-time observations. The analysis correlates records only after strictly checking all 360 traced kernels against their recorded order, kernel name, and grid/block configuration.

| seed | event Pred/Current paired-ratio median | nsys Pred/Current paired-ratio median | nsys Random/Pred paired-ratio median |
| --- | --- | --- | --- |
| 928 | 0.99636 | 1.01123 | 7.85345 |
| 929 | 0.99683 | 1.01367 | 7.89796 |
| 930 | 0.99879 | 1.01400 | 7.90814 |

All raw paired samples, per-seed min/median/max values, and aggregate distributions are archived; the best seed was not selected. **The small Current/Pred differences reverse direction between the two sampling methods; no stable Predicted benefit was observed.** Random kernels are substantially slower, as confirmed by nsys, but their hardware cause has not been established and cannot be attributed to coalescing/cache behavior. These results do not establish BFS as an optimal layout. For this fixture, switching to Predicted solely for resident kernels has no measured stable benefit. The smallest next step is to obtain counters and compare the same batch/profile, rather than first adding more complex reordering. This example does not support extrapolation to other data or scales.

Across the entire controlled replay, nsys measured H2D: 1116 copies, 6,880,648,464 bytes, and 0.62955s total pure copy time; D2H: 360 copies, 70,778,880 bytes, and 0.005756s. The 360 cuLaunchKernel API calls totaled 0.004095s; cuEventSynchronize totaled 10.64926s. These are trace-wide totals, including warmup, nine graph uploads, and private bindings. They are not per-kernel DRAM traffic/bandwidth counters, and API synchronization time must not be added as extra kernel time. Wall times for every upload, private H2D, D2H, and launch pair are retained in the raw records.

## Full-Run Costs and Process-Exit Limitations

| Instance | pack/reordering wall s | readonly graph H2D wall s | execution wall s for all outputs |
| --- | --- | --- | --- |
| Current | 328.52 pack | 0.06464 | 10.72 |
| Predicted | 266.74 pack (including prediction 6.90s) | 0.06614 | 10.76 |
| Random 928 | 78.71 reordering, additionally reusing Current pack | 0.06482 | 27.78 |
| Random 929 | 77.10 reordering, additionally reusing Current pack | 0.06412 | 27.80 |
| Random 930 | 79.81 reordering, additionally reusing Current pack | 0.06472 | 31.08 |

Full execution wall time includes batch preparation, binding H2D, kernels, D2H, the oracle, Scalar output-node materialization/validation, and binary saving. The raw records list these components separately. The pack times above include bounds checking and identity artifacts; production packing stages have separate timings. **CPU/JIT tests ran concurrently during packing, so these are resource observations from this run, not an isolated CPU performance comparison.** The 18m-node graph was not rebuilt to obtain more favorable CPU numbers.

**The full-run process ultimately exited with code 143 (SIGTERM), rather than normally with code 0; this was not a tool timeout.** After the complete computations for all five instances, zero-status checks, full binaries, and report.complete=true had been written, the process continued using CPU during Python interpreter shutdown cleanup. perf 6.8.12 collected 5s of cpu-clock:u data at 99Hz with DWARF sampling: 495 samples, lost=0. In that window, 95.35% of self samples were in gc_collect_main, with Py_FinalizeEx in the call chain. This identifies the hotspot only within the sampled window and does not explain all unmeasured overhead in the entire run.

After confirming that this process no longer had a CUDA context, SIGTERM was sent only to this process, whose computation had completed, to avoid interfering with formal sampling. The exit clock bracket was 1795.43–1795.68s (approximately 1s precision after epoch conversion), including graph construction, five instances, artifacts, and terminated cleanup; **it is not the end-to-end cost of a natural process exit**. No unmeasured normal full end-to-end speedup is reported, and resident kernel times cannot offset the actual one-time CPU graph construction/packing costs.

[Exit log](../../scripts/gpu_walker/large_matmul/validation/full-run-exit.log),
[termination record](../../scripts/gpu_walker/large_matmul/validation/termination.json),
and [CPU profiler report](../../scripts/gpu_walker/large_matmul/validation/cleanup-perf-report.txt).

## Reproduction, Evidence, and Checks

GPU: RTX3090, 24576MiB, driver580.65.06, CUDA driver API13000;
Python3.12.11, LLVM20.1.8 shim, nsys2025.3.2.367, ncu2025.3.0.0.
This environment was not assumed from an earlier report: the device, tools, and absence of external processes were checked again in this round.
PTX SHA256: `1dcb05c5f3cc1dfc7aa4a6ec3d79e4bc096f9b0842977b50183694db3131fdca`.

- [Tooling/semantics](../../scripts/gpu_walker/large_matmul/README.md);
  [exact commands/environment](../../scripts/gpu_walker/large_matmul/validation/commands.txt).
- [Full-result machine-readable summary](../../scripts/gpu_walker/large_matmul/validation/full-run.json).
- [Ordinary samples](../../scripts/gpu_walker/large_matmul/validation/ordinary.json),
  [nsys-correlated results](../../scripts/gpu_walker/large_matmul/validation/profile.json).
- [ncu failure log](../../scripts/gpu_walker/large_matmul/validation/ncu-predicted.log).
- [Local raw directory](/tmp/jac-large-matmul-3000-20261007), approximately 4.6GiB, containing all complete
  packed arrays/heads, identity arrays, five complete output binaries, PTX, source
  snapshots, and raw JSON/CSV. These large binaries were not added to the repository.
- [Raw nsys trace](/tmp/jac-large-matmul-3000-20261007/nsys-trace.nsys-rep),
  [SQLite](/tmp/jac-large-matmul-3000-20261007/nsys-trace.sqlite),
  [raw CPU perf](/tmp/jac-large-matmul-3000-20261007/cleanup.perf.data).
- The 15 existing named CPU/JIT tests passed in this round. 1 new bounded differential regression covers four shapes
  and Current/Predicted, checking that their actual node identity/CSR data matches the corresponding full lane pack.
  Actual CUDA small-scale trials, repeated resident replay, and all five complete 3000³ instances were correct.
- Named-only schema; the old Chain LLVM path was not retested in this round, and the global LLVM environment was not changed.

The exclusive GPU window was explicitly released, and the compute-process list was confirmed empty at the end. Other agents' files, untracked work, and the stash were preserved; there was no branch switch, commit, or push.
