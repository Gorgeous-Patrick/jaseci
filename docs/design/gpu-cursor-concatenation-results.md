# Cursor-Order Concatenated BFS: Actual Layouts, GPU Measurements, and Evidence Limits (2026-10-07)

The default `predicted` policy has been corrected to **concatenate each cursor's complete batch-wide multi-source BFS in cursor declaration order**: the complete a sequence comes first, followed by the complete b sequence, with any additional channels handled in order. A shared node identity appears only at its first occurrence; remaining nodes fall back to the original discovery order. The old rank-interleaved implementation has been removed, with no compatibility mode or remeasurement of the old policy. Execution FIFOs, repeated arrivals, joint triggers, lane order, and adjacency-row order are unchanged.

**Hardware-counter evidence gap: Nsight Compute 2025.3.0 actually returned `ERR_NVGPUCTRPERM`. There are no measured comparisons of coalescing, sector/request counts, cache hits, DRAM bytes/bandwidth, or occupancy, so GPU mechanisms cannot be explained. Drivers/system configuration were not changed, and sudo was not used or a password requested. The theoretical sector model below cannot substitute for hardware measurements.**

The lead agent coordinated the exclusive GPU window. At the start, `nvidia-smi` showed no compute processes, and the GPU was explicitly released after collection and correctness checks were complete. The historical numbers in the [2026-10-06 report](gpu-cursor-layout-results.md) are preserved; only an old-policy notice was added, without rewriting the raw data.

## 1. Did the Actual Layout Change?

For 4×4 and rectangular 3×5×2 matrices, identity labels are recovered from the actual packed heads/CSR. Identity is not inferred from values, and matrix coordinates are not passed to the packer. Every input and output Scalar has only one int; inputs are shared by identity rather than copied per product. Each row below gives the actual identity at that physical index:

### matmul-4x4x4

| Physical index | Current identity | New Predicted identity |
| ---: | --- | --- |
| 0 | A[0,0] | A[0,0] |
| 1 | B[0,0] | A[1,0] |
| 2 | B[0,1] | A[2,0] |
| 3 | B[0,2] | A[3,0] |
| 4 | B[0,3] | A[0,1] |
| 5 | A[1,0] | A[1,1] |
| 6 | A[2,0] | A[2,1] |
| 7 | A[3,0] | A[3,1] |
| 8 | A[0,1] | A[0,2] |
| 9 | B[1,0] | A[1,2] |
| 10 | B[1,1] | A[2,2] |
| 11 | B[1,2] | A[3,2] |
| 12 | B[1,3] | A[0,3] |
| 13 | A[1,1] | A[1,3] |
| 14 | A[2,1] | A[2,3] |
| 15 | A[3,1] | A[3,3] |
| 16 | A[0,2] | B[0,0] |
| 17 | B[2,0] | B[0,1] |
| 18 | B[2,1] | B[0,2] |
| 19 | B[2,2] | B[0,3] |
| 20 | B[2,3] | B[1,0] |
| 21 | A[1,2] | B[1,1] |
| 22 | A[2,2] | B[1,2] |
| 23 | A[3,2] | B[1,3] |
| 24 | A[0,3] | B[2,0] |
| 25 | B[3,0] | B[2,1] |
| 26 | B[3,1] | B[2,2] |
| 27 | B[3,2] | B[2,3] |
| 28 | B[3,3] | B[3,0] |
| 29 | A[1,3] | B[3,1] |
| 30 | A[2,3] | B[3,2] |
| 31 | A[3,3] | B[3,3] |

Identity-order SHA256: Current `bcc9bcfc670935c6018dc26a74956a373b655f8930dd55ab074d816d7d233780`; Predicted `1f70283cd73e5351a5550bc41f6fc4cb862b086ea750538beedc54d10a0c9aba`.

### matmul-3x5x2

| Physical index | Current identity | New Predicted identity |
| ---: | --- | --- |
| 0 | A[0,0] | A[0,0] |
| 1 | B[0,0] | A[1,0] |
| 2 | B[0,1] | A[2,0] |
| 3 | A[1,0] | A[0,1] |
| 4 | A[2,0] | A[1,1] |
| 5 | A[0,1] | A[2,1] |
| 6 | B[1,0] | A[0,2] |
| 7 | B[1,1] | A[1,2] |
| 8 | A[1,1] | A[2,2] |
| 9 | A[2,1] | A[0,3] |
| 10 | A[0,2] | A[1,3] |
| 11 | B[2,0] | A[2,3] |
| 12 | B[2,1] | A[0,4] |
| 13 | A[1,2] | A[1,4] |
| 14 | A[2,2] | A[2,4] |
| 15 | A[0,3] | B[0,0] |
| 16 | B[3,0] | B[0,1] |
| 17 | B[3,1] | B[1,0] |
| 18 | A[1,3] | B[1,1] |
| 19 | A[2,3] | B[2,0] |
| 20 | A[0,4] | B[2,1] |
| 21 | B[4,0] | B[3,0] |
| 22 | B[4,1] | B[3,1] |
| 23 | A[1,4] | B[4,0] |
| 24 | A[2,4] | B[4,1] |

Identity-order SHA256: Current `2a0a16a7ce85c211f6b6e8a758e7ec09f9fd77e230e81d74c30a857dd51e2de6`; Predicted `860683d08c5e487f7fb5f350d2a6e3d093d0524fa383f9e42a4d5cfe26e89621`.

For 4×4, all A identities for a occupy indices 0–15, and all B identities for b occupy 16–31. For the rectangular case, A occupies 0–14 and B occupies 15–24. Within each channel, the entire batch's seeds are placed first, followed by successive BFS levels; complete paths are not concatenated walker by walker.

The [complete small-matrix audit](../../dist/gpu-cursor-concat-20261007/audit-named/audits.json) retains indices, identities, projected values, raw typed arrays, and per-column hashes. Every formal benchmark case is also reconstructed on the CPU. An identity-order audit is accepted only when the dtype/count/SHA256 of every array for every layout exactly matches the measured data:

| Case | Changed identity positions / node count | All array hashes identical for Current/Predicted |
| --- | ---: | --- |
| dot-128x8 | 2046 / 2048 | No |
| dot-1024x32 | 65534 / 65536 | No |
| matmul-4x4x4 | 31 / 32 | No |
| matmul-3x5x2 | 24 / 25 | No |
| matmul-16x32x24 | 1279 / 1280 | No |
| matmul-32x64x48 | 5119 / 5120 | No |
| matmul-64x128x64 | 16383 / 16384 | No |

See the [complete identity/array audit](../../dist/gpu-cursor-concat-20261007/benchmark-identity-audit/layout-identity-audit.json). Dot also has an actual permutation difference in this round, unlike yesterday's interleaved policy, where Current and Predicted were identical.

## 2. Measured Coalescing / Cache / DRAM Differences

**Hardware differences cannot be determined.** Running ncu as an ordinary user checked current permissions on an actual kernel and failed. Logs: [original `/tmp` log](/tmp/jac-concat-ncu-probe.log) and [retained copy](../../dist/gpu-cursor-concat-20261007/jac-concat-ncu-probe.log). Read-only driver information reports `RmProfilingAdminOnly: 1`. No valid counter report/metric CSV was generated. Catalogue queries establish only which metrics the tool offers; they are not measurements.

An independent [theoretical address model](../../dist/gpu-cursor-concat-20261007/benchmark/theoretical-sectors.json) calculates 32-byte sectors separately for each cursor, logical load, warp, and round. It does not combine different loads or rounds into one request. It assumes a 256-byte-aligned arena base, 8-byte scalars, and 32 lanes per warp. Its scope is the unconditional, single-successor, single-seed Dot used here; conditional/branching modes are rejected. The model does not represent executed instructions, hardware requests, cache misses, or DRAM traffic, and does not simulate backend optimizations or cache reuse.

For 64×128×64, median distinct sectors per logical load are listed below. Random uses seed 928 as an example; all seeds are in the raw JSON:

| Channel / logical load | Current | New Predicted | Random-928 |
| --- | ---: | ---: | ---: |
| node_value.column_0.cursor_0 | 1 | 1 | 1 |
| node_value.column_0.cursor_1 | 9 | 8 | 32 |
| tag.cursor_1 | 9 | 8 | 32 |
| csr_begin.cursor_1 | 9 | 9 | 32 |
| csr_end.cursor_1 | 9 | 9 | 32 |
| csr_target.cursor_1 | 8 | 8 | 32 |

The change here concerns the theoretical address coverage of value/tag loads, not all CSR loads. The `node_count+1` displacement in the CSR plane is also included in exact address calculations. The raw JSON records the specific byte addresses/sector IDs for the first warp's first two rounds so each item can be checked. This does not establish fewer actual transactions or explain the GPU rankings below.

## Environment, Kernel, and Experimental Method

The actual device was an RTX 3090 with driver **580.65.06**; Python **3.12.11**, LLVM **20.1.8** (an isolated `/tmp` llvmlite 0.46.0 shim), nsys **2025.3.2.367**, and ncu **2025.3.0.0**. Yesterday's driver/Python/Nsight configuration was not reused. Source revision was `3505f21febf7a92dcedebd0f59d315f1e4965a88`, with an uncommitted working tree. Hashes of key files and source snapshots matching the measurement hashes exactly have been retained. GPU clocks were not locked.

All layouts and cases use the same `jac_Dot_cursors_batch`, PTX SHA256 `1dcb05c5f3cc1dfc7aa4a6ec3d79e4bc096f9b0842977b50183694db3131fdca`, PTX 6.0 / sm_70, block=128. Each case uses the same input, dtype=int64, lanes, grid, and resource parameters across layouts. Random only permutes the unified, deduplicated physical node indices, remapping every column/head/CSR row and target while preserving within-row order and lane assignment.

Seeds 928/929/930 each use 6 warmup rounds and 16 paired repetitions, with deterministic randomization of layout order within each pair. Every launch checks all lanes against an independent CPU oracle and the Current result; representative lanes also run actual Jac CPU walkers. The number of input nodes is `(M+N)*K`, with explicit node/lane/payload limits controlling scale. Ordinary timing and nsys replay are separate, and the names/geometries/order of all 2,807 kernels are strictly aligned.

This round uses the named-only path with lazy loading of the requested schema. The old Chain schema's LLVM pass-builder ABI mismatch was outside this task, and **the old Chain regressions were not rerun in this round**. The 15 named tests passed on CPU/JIT/actual CUDA, covering 3/7 cursors, shared identity, empty/unequal queues, repeated arrivals, CSR branching, conditional visits, loops, reports, and new regressions for complete concatenation/fallback/shared order. 2 physical-permutation/summary-boundary tests also passed.

## Timing Observations and Distributions

The first independent nsys resident-kernel run is reported below in μs, as median [p10,p90], rather than event intervals. Every cell includes all three seeds; the fastest seed was not selected:

| Case | Current | New Predicted | Random |
| --- | ---: | ---: | ---: |
| dot-1024x32 | 77.681 [48.161,78.433] | 77.440 [47.488,77.953] | 96.881 [69.313,97.985] |
| dot-128x8 | 14.976 [14.944,15.009] | 14.848 [14.784,14.912] | 15.776 [15.489,16.064] |
| matmul-16x32x24 | 47.297 [47.200,47.360] | 47.329 [47.201,47.392] | 44.400 [44.128,45.472] |
| matmul-32x64x48 | 93.024 [92.801,93.089] | 92.736 [92.641,92.833] | 98.080 [97.760,98.369] |
| matmul-3x5x2 | 7.712 [7.680,7.712] | 7.200 [7.168,7.232] | 6.816 [6.464,7.040] |
| matmul-4x4x4 | 6.720 [6.688,6.721] | 6.784 [6.720,6.784] | 5.968 [5.728,6.368] |
| matmul-64x128x64 | 237.266 [184.481,253.794] | 259.522 [183.970,268.514] | 238.674 [200.834,243.458] |

Wide-distribution cases received additional controlled replay with fixed inputs, no build/pack work, 16 warmup rounds, and 64 repetitions per seed. Ordinary events were collected separately, followed by a separate nsys replay. The first supplemental set of ordinary samples overlapped with CPU trace extraction and is retained, but the report uses `controlled-normal-isolated`, which ran without concurrent CPU analysis. Original samples were not overwritten.

Controlled nsys paired **Predicted/Current** ratios follow; values below 1 mean Predicted was faster:

| Case | seed 928 median | seed 929 median | seed 930 median | Combined median [p10,p90] |
| --- | ---: | ---: | ---: | ---: |
| dot-1024x32 | 0.9840 | 0.9852 | 0.9864 | 0.9853 [0.6451,1.0023] |
| matmul-64x128x64 | 1.0131 | 0.9739 | 0.9778 | 0.9806 [0.7586,1.2710] |

For the large MatMul, the first run's paired Predicted/Current medians across the three seeds were 1.0562/1.0607/1.0734. Controlled replay spans 1, and the Random ranking also differs between ordinary events and nsys. A single run's median cannot establish a stable benefit or regression. Dot's median difference relative to Random is reproducibly observable, while the new Predicted/Current difference is small and depends on the run. No statistical significance is claimed, and the differences are not attributed to coalescing/cache behavior. The faster Random results for small MatMul are also retained as negative results, with their GPU cause unknown.

## Profiling Observations on Packing, Copies, and Application Cost

Ordinary timing separately records build, collection, prediction, SoA/remap, random permutation, host H2D/D2H APIs, events, and execution wall time. Event intervals may include enqueue gaps; nsys separately reports precise kernel/device-copy/launch-API durations. These are not treated as the same timing measure.

One-shot costs in ms, using the median of paired samples for each layout:

| Case / metric | Current | New Predicted | Random |
| --- | ---: | ---: | ---: |
| matmul-3x5x2 / pack | 0.3623 | 0.3777 | 0.4504 |
| matmul-3x5x2 / H2D | 0.1089 | 0.1084 | 0.1087 |
| matmul-3x5x2 / D2H | 0.0170 | 0.0171 | 0.0171 |
| matmul-3x5x2 / pack_through_D2H | 0.6487 | 0.6612 | 0.7366 |
| matmul-3x5x2 / graph_through_D2H | 0.8255 | 0.8380 | 0.9135 |
| matmul-4x4x4 / pack | 0.4821 | 0.4967 | 0.5817 |
| matmul-4x4x4 / H2D | 0.1105 | 0.1101 | 0.1099 |
| matmul-4x4x4 / D2H | 0.0171 | 0.0168 | 0.0169 |
| matmul-4x4x4 / pack_through_D2H | 0.7687 | 0.7817 | 0.8657 |
| matmul-4x4x4 / graph_through_D2H | 0.9972 | 1.0101 | 1.0941 |
| matmul-64x128x64 / pack | 294.7695 | 297.0577 | 298.4864 |
| matmul-64x128x64 / H2D | 0.2588 | 0.2579 | 0.2437 |
| matmul-64x128x64 / D2H | 0.0282 | 0.0279 | 0.0276 |
| matmul-64x128x64 / pack_through_D2H | 295.5495 | 297.8059 | 299.3431 |
| matmul-64x128x64 / graph_through_D2H | 464.8301 | 467.0865 | 468.6237 |

pack-through-D2H combines packing and execution wall time; graph-through-D2H adds independently measured build time. **Neither is a complete application wall timer including cold-context initialization, validation, and final output-node publication.** Steady-state one-shot runs reuse the session; resident mode excludes input upload, and output poisoning and validation are outside the kernel timer. The full limitations are stated in the timing contract; these measurements are not presented as cold-start end-to-end speedups.

For the nsys 4×4 Current one-shot run, total device H2D was 4.320 μs, D2H was 1.664 μs, and the cuLaunchKernel API took 6.065 μs; the pure resident kernel took approximately 6.720 μs. For 64×128×64 Current, the corresponding device-copy durations were 84.081/5.376 μs, and launch API duration was 6.670 μs. API and device work can overlap and must not be added directly. Copy duration is not used to infer a device-memory-bandwidth bottleneck.

Large MatMul packing currently takes approximately 295–299 ms, while kernels take hundreds of μs. The ordinary median for Predicted's prediction stage is 5.728 ms. When repacking on every run, these CPU costs greatly exceed the observed microsecond-scale kernel differences. The CPU [process-time cProfile](../../dist/gpu-cursor-concat-20261007/cpu-profile-process-time/cpu-profile.json) was collected independently of GPU measurements, with three packs: Current pack_cursors totaled 4.641 CPU s, including 1.526 s in nested walk; Predicted predict_layout took 0.264 s; Random permute_cursors took 0.590 s. This supports the conclusion that queries/prediction/reordering consume actual CPU time, but does not replace ordinary timing. Timer/profiler overhead is substantial, and nested cumulative times must not be added.

Applicable conclusion: the actual concatenation policy is implemented, but this set of shared-input MatMul cases does not establish stable resident benefits. For one-shot use, a small, unstable kernel difference does not justify extra prediction. Cache/memory-access/occupancy explanations remain open. The smallest next validation is to obtain usable ordinary-user counter permissions, collect sector/request/cache/DRAM metrics for the same kernel/data, and reuse a packed resident batch to evaluate layout in isolation. Theoretical sector counts are not used to promise optimization benefits in advance.

## Reproduction and Raw Evidence

```sh
export XDG_CACHE_HOME=/tmp/jac-cursor-concat-cache
export JAC_CACHE_HOME=/tmp/jac-cursor-concat-cache/jac
export JAC_PG_DIST=/home/baichuan/.cache/jac/pg/dist/linux-amd64-18.6.0
export JAC_LLVM_SHIM=/tmp/jac-cursor-llvm/llvmlite/binding/libllvmlite.so
export PYTHONPATH=jac
# llvmlite 0.46.0 installed only under /tmp/jac-cursor-llvm; shared env unchanged
env/bin/python scripts/gpu_walker/compare_named_layouts.py \
  --chain-cases --dot-cases 128x8 1024x32 \
  --matmul-cases 4x4x4 3x5x2 16x32x24 32x64x48 64x128x64 \
  --seeds 928 929 930 --warmup 6 --repeats 16 --profile \
  --output /tmp/jac-layout-cursor-concat-20261007
```

Use a new output directory when repeating the experiment to avoid overwriting existing samples. Coordinate the GPU window first; CPU audit/model/profile runs do not request the device. Complete commands, versions, environment, and source/shim/PTX hashes are in the [collection metadata](../../dist/gpu-cursor-concat-20261007/profiling-evidence.json).

- [Machine-readable report and per-seed paired distributions](../../scripts/gpu_walker/validation/cursor_concatenation_3090_20261007.json)
- [Ordinary CSV](/tmp/jac-layout-cursor-concat-20261007/wall-events.csv), [inputs/hashes](/tmp/jac-layout-cursor-concat-20261007/inputs.json)
- [Original nsys report](/tmp/jac-layout-cursor-concat-20261007/trace.nsys-rep), [SQLite](/tmp/jac-layout-cursor-concat-20261007/trace.sqlite), [per-launch CSV](/tmp/jac-layout-cursor-concat-20261007/profile-launches.csv)
- [Controlled nsys](/tmp/jac-layout-cursor-concat-20261007/controlled-trace.nsys-rep), [controlled paired CSV](/tmp/jac-layout-cursor-concat-20261007/controlled-profile/records.csv), [controlled ordinary CSV](/tmp/jac-layout-cursor-concat-20261007/controlled-normal-isolated/records.csv)
- [Kernel/copy/API correlation observations](/tmp/jac-layout-cursor-concat-20261007/trace-facts.json), [counter failure](/tmp/jac-concat-ncu-probe.log)
- [15 CUDA regressions](/tmp/jac-concat-cuda-tests.log), [CPU/JIT regressions](/tmp/jac-concat-host-tests.log), [supplemental MatMul CPU/JIT](/tmp/jac-concat-matmul-host.log)

A complete raw copy (typed arrays, all samples, source snapshots, profiler/.prof files, theoretical per-address data, and SHA manifests) is in `dist/gpu-cursor-concat-20261007/`. Main changes: merge order in gpu_cursors.py; three meaningful regressions in test_named_cursors.py; lazy loading of the requested schema and strategy labels in runner/replay/profile helpers; new actual MatMul audits and a theoretical address model; semantics and results documentation. There was no branch switch, commit/push, or overwrite of root-directory images, env, output, task.c/task_bins, or other agents' files; the stash was unchanged.
