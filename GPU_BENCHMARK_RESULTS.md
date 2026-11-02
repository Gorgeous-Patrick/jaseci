# Jac GPU benchmark results: RTX 3090, 2026-11-02

First full execution of the benchmarks in this PR. All suites completed, and
every CPU and GPU output was checked against an independent oracle on every
round. Raw output (`results.json`, traces, `REPORT.md`, `REPORT.pdf`) is kept
on the host at `~/jac-benchmark-runs/20261102T173527Z/`.

## Summary

The two suites answer different questions, so their numbers are never
compared directly:

| Suite | Question | Measures | Units |
| --- | --- | --- | --- |
| Layout | Does reordering nodes in memory make the same GPU kernel faster? | GPU kernel time only (Nsight Systems) | microseconds |
| Applications | Is one public `run_walkers` GPU call faster than running the same walkers in Jac? | Whole call: packing, transfer, kernel, copyback, publication | milliseconds |

What went well:

- **Layout wins at scale.** The predicted layout makes the identical kernel
  1.11x, 1.14x and 1.75x faster on the three larger matrices, consistently
  across three random seeds.
- **The GPU path is correct.** Every result matched the oracle in all 19
  application cases and every round.
- **Shared-graph applications are much faster than Jac.** dependency,
  hierarchy and network_outage run 9x to 94x faster than serial Jac.

What did not:

- **Layout hurts tiny matrices** (6% to 12% slower at the two smallest sizes).
- **Jac's kernel is 5x to 34x slower than tiled CUDA**, even with the better
  layout. This is the largest gap in the results.
- **Applications where each walker has its own nodes gain only 1.6x to 3.4x**
  (sparse_rows, sequence, fraud_screening).
- **The application baseline is interpreted Jac**, which inflates every
  application ratio. None of them is a GPU vs native CPU comparison.

## 1. Layout benchmark

Both Jac arms run the same checked LLVM O2 PTX; only the order of nodes in
memory changes. "Ratio" is Random time divided by Predicted time, so above 1
means the predicted layout is faster.

| Matrix (M x K x N) | Random (us) | Predicted (us) | Ratio | Same for all 3 seeds? | Tiled CUDA (us) | Jac slower than CUDA by |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| 3 x 5 x 2 | 6.18 | 7.04 | **0.88** | yes (0.88 to 0.96) | 1.54 | 4.6x |
| 17 x 31 x 19 | 41.1 | 43.9 | **0.94** | yes (0.94) | 2.14 | 20x |
| 64 x 128 x 64 | 195.7 | 176.2 | **1.11** | yes (1.11) | 5.31 | 33x |
| 128 x 128 x 128 | 187.3 | 164.2 | **1.14** | yes (1.14) | 4.83 | 34x |
| 256 x 256 x 256 | 947.6 | 542.7 | **1.75** | yes (1.73 to 1.75) | 20.4 | 27x |

How the sizes compare:

- **The benefit grows with size.** The ratio rises from 0.88 to 1.75 as the
  matrix grows. The two smallest cases use only 6 and 323 GPU threads on an
  82-SM GPU, so launch and latency cost dominate and placement cannot help.
- **Layout vs code generation.** At 256^3 the better layout saves 405 us,
  while the remaining gap to CUDA is 522 us. Closing the code-generation gap
  matters as much as layout. The CUDA kernel uses shared-memory tiling, a
  different algorithm, so this is a whole-implementation gap, not compiler
  overhead alone.
- **The noise is far smaller than the effects.** p10 to p90 is within about
  1% of the median for most arms (about 6% for Random at 256^3).

What it means for us: placement-aware compilation is worth pursuing, with a
size threshold below which reordering is skipped. This is evidence from one
kernel (matrix multiply); other walker kernels are untested. The baseline is
a random shuffle, not the production default layout, so the gain over
today's behavior is still unmeasured. Nsight Compute counters were blocked
(`ERR_NVGPUCTRPERM`), so there are no measured cache numbers explaining why
the large case benefits most.

## 2. Application benchmarks

### One number explains the results: visits per node

Putting all six applications on the same scale shows two nearly constant
costs:

- Serial Jac costs about **12 to 24 us per node visit**.
- The GPU call costs about **6 to 21 us per node in the graph**, whether or
  not that node is visited many times.

So the GPU's speedup is roughly the average number of times each node is
visited. Applications that revisit the same nodes win big; applications that
touch each node once win about 2x.

| App | Graph shape | Shared between walkers? | Visits per node (largest case) | GPU speedup (largest case) |
| --- | --- | --- | ---: | ---: |
| dependency (deep-shared) | layered DAG, paths multiply | yes | 150 | **94x** |
| hierarchy | site / building / device tree | yes | 48 | **59x** |
| network_outage | core / region / access tree, pruned links | yes | 28 | **29x** |
| fraud_screening | payer, transfer, shared recipient | partly (recipients only) | 2.0 | 2.3x |
| sparse_rows | one small star per row | no | 1.0 | 2.3x |
| sequence | one chain per walker | no | 1.0 | 1.6x |

Within each application the same rule holds as size grows:

- hierarchy: 14, 24, then 48 visits per node gives 12x, 31x, then 59x.
- network_outage: 8, 14, then 28 visits per node gives 10x, 20x, then 29x.
- dependency: 8 and 7 visits per node give about 9x; 150 gives 94x.
- sparse_rows, sequence and fraud_screening stay at 1 to 2 visits per node,
  so their speedup stays flat at about 2x however large they get.

### Why the GPU cost follows nodes, not work

Each `run_walkers` call packs the reachable graph into GPU buffers in Python
before launching. Device payloads are at most 5.5 MB (well under a
millisecond to transfer), so the steady per-node cost is most likely that
Python packing. This is an inference from how the timings scale; packing was
not timed separately in this run (see next steps).

### What it means for us

- **Good fit:** many walkers over one shared graph (monitoring trees, DAG
  analysis, impact propagation). Speedups here are large and grow with load.
- **Poor fit today:** one walker per private subgraph. The per-node cost of
  the call cancels most of the GPU's advantage.
- **Likely cheapest improvement:** reduce or reuse packing between calls (for
  example, keep a packed graph on the GPU across batches). If packing is the
  per-node cost, this would lift every application, the poor-fit ones most.
- **Interpret carefully:** the baseline is interpreted Jac. A native CPU
  traversal would be much faster than about 15 us per visit, so these
  ratios show that the GPU runtime beats ordinary Jac, not that a GPU beats a
  CPU.
- **Correctness held everywhere**, including repeated DAG arrivals
  (dependency) and pruned propagation (network_outage).

## Next steps

1. Time `gpu.prepare()` (packing) separately from execution to confirm where
   the per-node cost goes.
2. Add the production default layout as an arm in the layout suite.
3. Scale the applications to 10^5 to 10^6 walkers and nodes.
4. Keep three distinct application shapes for timing (shared tree or DAG,
   chain, irregular fan-out); keep the rest as correctness tests.
5. Add a native CPU baseline, and lock clocks or flush L2 between replays if
   root access is available.

## Appendix A: environment

| Item | Value |
| --- | --- |
| Host | clarity1.eecs.umich.edu, Pop!_OS 22.04, x86_64, 20 cores, 62 GB RAM |
| GPU | NVIDIA GeForce RTX 3090 (sm_86, 24 GB, 82 SMs, 6 MB L2), driver 595.71.05 |
| Toolkit | CUDA 12.9 (nvcc V12.9.86), Nsight Systems 2025.1.3, Nsight Compute 2025.2.1 |
| Jac | 0.37.17, dev build (`zig build -Ddev`) from this branch at `d30b0d46d` |
| Protocol | 3 warmup + 15 measured rounds, randomized arm order, medians reported |
| GPU sharing | Two other users' processes held about 1.4 GB but were idle (0% utilization) before and after each application run. Clocks were not locked (no root). |
| Tests | Layout 17/17 passed; all six application test files passed. |

## Appendix B: all application cases

GPU = one full `run_walkers` call. Serial = the same walkers in interpreted
Jac (`--backend python`). Speedup = serial / GPU. The first GPU warmup call of
each case (CUDA session start, 75 to 880 ms) is excluded. Measured GPU rounds
varied by a few percent.

| App | Case | Nodes | Walkers | Visits | Visits per node | Serial ms | GPU ms | Speedup |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dependency | wide-shallow | 256 | 256 | 2,152 | 8.4 | 43.3 | 4.91 | 8.8x |
| dependency | deep-shared | 256 | 256 | 38,272 | 149.5 | 494.5 | 5.28 | 93.6x |
| dependency | irregular | 448 | 512 | 3,032 | 6.8 | 69.7 | 8.23 | 8.5x |
| hierarchy | one-site | 70 | 32 | 956 | 13.7 | 13.7 | 1.15 | 11.9x |
| hierarchy | four-sites | 1,061 | 256 | 25,680 | 24.2 | 324.3 | 10.5 | 30.8x |
| hierarchy | eight-sites | 4,169 | 1,024 | 200,688 | 48.1 | 2,432.7 | 41.2 | 59.1x |
| network_outage | campus | 101 | 32 | 777 | 7.7 | 12.1 | 1.22 | 9.9x |
| network_outage | metro | 604 | 256 | 8,639 | 14.3 | 127.4 | 6.46 | 19.7x |
| network_outage | regional | 1,608 | 1,024 | 44,779 | 27.8 | 639.7 | 21.9 | 29.3x |
| fraud_screening | branch-64 | 335 | 64 | 574 | 1.7 | 11.5 | 4.56 | 2.5x |
| fraud_screening | regional-256 | 4,439 | 256 | 8,494 | 1.9 | 125.6 | 52.5 | 2.4x |
| fraud_screening | network-1024 | 34,029 | 1,024 | 66,522 | 2.0 | 917.2 | 399.0 | 2.3x |
| sparse_rows | small-128x8 | 640 | 128 | 640 | 1.0 | 15.6 | 4.64 | 3.4x |
| sparse_rows | batch-1024x8 | 5,125 | 1,024 | 5,125 | 1.0 | 124.3 | 36.4 | 3.4x |
| sparse_rows | irregular-1024x64 | 33,756 | 1,024 | 33,756 | 1.0 | 463.1 | 201.6 | 2.3x |
| sparse_rows | irregular-4096x64 | 135,136 | 4,096 | 135,136 | 1.0 | 1,854.6 | 815.2 | 2.3x |
| sequence | 64 x 8 | 512 | 64 | 512 | 1.0 | 10.8 | 4.89 | 2.2x |
| sequence | 256 x 32 | 8,192 | 256 | 8,192 | 1.0 | 127.6 | 72.0 | 1.8x |
| sequence | 1024 x 64 | 65,536 | 1,024 | 65,536 | 1.0 | 966.6 | 592.4 | 1.6x |

Visits for dependency and network_outage were recomputed from each runner's
own oracle, since their `results.json` does not store totals.
