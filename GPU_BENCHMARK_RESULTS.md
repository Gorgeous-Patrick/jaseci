# Jac GPU benchmark results: RTX 3090, 2026-11-02

First full execution of the benchmarks in this PR. All suites completed, and
every CPU and GPU output was checked against an independent oracle on every
round. The raw output directory (`results.json`, traces, `REPORT.md`,
`REPORT.pdf`) is kept on the host at
`~/jac-benchmark-runs/20261102T173527Z/`.

## Environment

| Item | Value |
| --- | --- |
| Host | clarity1.eecs.umich.edu, Pop!_OS 22.04, x86_64, 20 cores, 62 GB RAM |
| GPU | NVIDIA GeForce RTX 3090 (sm_86, 24 GB), driver 595.71.05 |
| Toolkit | CUDA 12.9 (nvcc V12.9.86), Nsight Systems 2025.1.3, Nsight Compute 2025.2.1 |
| Jac | 0.37.17, dev build (`zig build -Ddev`) from this branch at `d30b0d46d` |
| Protocol | 3 warmup + 15 measured rounds, randomized arm order, medians reported |
| GPU sharing | Two other users' processes held about 1.4 GB but were idle (0% utilization) before and after each app run. Clocks were not locked (no root). |

Tests on the host: layout 17/17 passed; all six app test files passed.

## 1. Layout benchmark (kernel time only)

Same checked LLVM O2 PTX for both Jac arms; only node placement changes.
Times are Nsight Systems kernel medians in microseconds. Ratio = Random /
Predicted, so above 1 means the predicted layout is faster.

| M x K x N | Random928 | Predicted | Ratio | Seeds 928/929/930 | CUDA O3 tiled | Jac / CUDA |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| 3 x 5 x 2 | 6.18 | 7.04 | 0.88 | 0.88 / 0.96 / 0.93 | 1.54 | 4.6x |
| 17 x 31 x 19 | 41.1 | 43.9 | 0.94 | 0.94 / 0.94 / 0.94 | 2.14 | 20x |
| 64 x 128 x 64 | 195.7 | 176.2 | 1.11 | 1.11 / 1.11 / 1.11 | 5.31 | 33x |
| 128 x 128 x 128 | 187.3 | 164.2 | 1.14 | 1.14 / 1.14 / 1.14 | 4.83 | 34x |
| 256 x 256 x 256 | 947.6 | 542.7 | 1.75 | 1.75 / 1.75 / 1.73 | 20.4 | 27x |

Spread is small: p10 to p90 is within about 1% of the median for most arms
(about 6% for Random at 256^3). Nsight Compute counters were unavailable
(`ERR_NVGPUCTRPERM`), so there are no measured cache-miss numbers.

## 2. Application benchmarks (whole public runtime call)

GPU time is one full `GpuWalkerRuntime.run_walkers` call: Python graph
packing, transfers, kernel, copyback and field publication. Serial time is
the same walkers run by interpreted Jac (`--backend python`). Ratio =
serial / GPU.

| App | Case | Graph nodes | Walkers | Device payload | Serial ms | GPU ms | Ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| hierarchy | one-site | 70 | 32 | not recorded | 13.7 | 1.15 | 11.9 |
| hierarchy | four-sites | 1,061 | 256 | not recorded | 324.3 | 10.5 | 30.8 |
| hierarchy | eight-sites | 4,169 | 1,024 | not recorded | 2,432.7 | 41.2 | 59.1 |
| dependency | wide-shallow | 256 | 256 | 45 KB | 43.3 | 4.91 | 8.8 |
| dependency | deep-shared | 256 | 256 | 291 KB | 494.5 | 5.28 | 93.6 |
| dependency | irregular | 448 | 512 | 65 KB | 69.7 | 8.23 | 8.5 |
| network_outage | campus | 101 | 32 | 17 KB | 12.1 | 1.22 | 9.9 |
| network_outage | metro | 604 | 256 | 174 KB | 127.4 | 6.46 | 19.7 |
| network_outage | regional | 1,608 | 1,024 | 886 KB | 639.7 | 21.9 | 29.3 |
| sparse_rows | small-128x8 | 640 | 128 | 86 KB | 15.6 | 4.64 | 3.4 |
| sparse_rows | batch-1024x8 | 5,125 | 1,024 | 684 KB | 124.3 | 36.4 | 3.4 |
| sparse_rows | irregular-1024x64 | 33,756 | 1,024 | 1.4 MB | 463.1 | 201.6 | 2.3 |
| sparse_rows | irregular-4096x64 | 135,136 | 4,096 | 5.5 MB | 1,854.6 | 815.2 | 2.3 |
| sequence | 64 x 8 | 512 | 64 | 23 KB | 10.8 | 4.89 | 2.2 |
| sequence | 256 x 32 | 8,192 | 256 | 339 KB | 127.6 | 72.0 | 1.8 |
| sequence | 1024 x 64 | 65,536 | 1,024 | 2.7 MB | 966.6 | 592.4 | 1.6 |
| fraud_screening | branch-64 | 335 | 64 | 30 KB | 11.5 | 4.56 | 2.5 |
| fraud_screening | regional-256 | 4,439 | 256 | 368 KB | 125.6 | 52.5 | 2.4 |
| fraud_screening | network-1024 | 34,029 | 1,024 | 2.8 MB | 917.2 | 399.0 | 2.3 |

The first GPU warmup call of each case (CUDA session start) took 75 to 880 ms
and is excluded. Measured GPU rounds varied by a few percent (interquartile
range).

## What each result means for us

### Layout benchmark

- **Layout matters once the working set is large.** At 256^3 the predicted
  layout removes 43% of kernel time, and the result is the same for every
  random seed. That is real evidence that placement-aware compilation pays
  off on memory-bound walker kernels.
- **It slightly hurts tiny graphs.** At 3x5x2 and 17x31x19 the predicted
  layout is 6 to 12% slower. These cases use 6 and 323 lanes on an 82-SM GPU,
  so they mostly measure launch and latency cost. The layout heuristic
  should probably be skipped below some size.
- **The bigger gap is code generation, not layout.** Even with the better
  layout, Jac's kernel is 5 to 34x slower than a tiled CUDA kernel. That
  CUDA kernel is a different algorithm (shared-memory tiling), so this is a
  whole-implementation gap, but it is where most remaining performance is.
- **Baseline caveat.** The comparison is predicted vs a random shuffle, not
  vs the production default layout. The gain over today's behavior is not
  yet measured.

### Application benchmarks

- **GPU time follows the number of nodes packed, not the work done.**
  sparse_rows packs about 135k nodes and takes 815 ms; hierarchy packs 4k
  nodes and takes 41 ms despite 200k visits. Device payloads are at most
  5.5 MB, so transfers are not the cost. The public call re-packs the graph
  in Python every time, and that dominates. These numbers measure
  runtime overhead far more than GPU compute.
- **Shared-graph workloads win big.** hierarchy (up to 59x), dependency (up to
  94x) and network_outage (up to 29x) run many queries over one small graph,
  so packing is cheap and each node is visited many times. dependency
  deep-shared is the extreme case: paths multiply through the DAG (up to 255
  visits per query from 256 tasks).
- **One-graph-per-walker workloads barely win.** sparse_rows, sequence and
  fraud_screening give each walker its own nodes, so packing grows with the
  work and the ratio settles near 2x. sequence is lowest (1.6x) because a
  chain gives the GPU no parallelism inside a walker.
- **The baseline inflates every ratio.** Serial means interpreted Jac. A
  native CPU traversal would be far faster, so these ratios are not GPU vs
  CPU speedups.
- **Correctness is the solid result.** Every walker output, field
  publication and status matched the independent oracle across 6 apps, 19
  cases and 18 rounds each, including repeated DAG arrivals and pruned
  propagation edges.

## Next steps

1. Time `gpu.prepare()` (packing) separately from execution, so the app
   suite reports packing, kernel and publication separately.
2. Add the production default layout as an arm in the layout suite.
3. Scale the apps to 10^5 to 10^6 walkers and nodes to find the crossover.
4. Keep three distinct app shapes (shared tree or DAG, chain, irregular
   fan-out) for timing; keep the rest as correctness tests.
5. Add a native CPU baseline, and lock clocks or flush L2 between replays if
   root access is available.
