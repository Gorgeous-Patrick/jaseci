# Weighted event-chain application benchmark

The Jac [model](model.jac) scores a stream of transaction events. Each event
stores an amount, a weight, an adjustment, and an active flag. One `RiskScore`
walker follows a finite `Next` chain, counts every event visited, and adds
`amount * weight + adjustment` for active events. This uses the existing
integer, multiple-field chain path; no new GPU compiler feature is assumed.

The [benchmark](benchmark.jac) constructs disjoint chains of fixed length for
three cases: 64 walkers × 8 events, 256 × 32, and 1024 × 64. Values come from
fixed integer formulas. An arithmetic oracle computes every expected final
score independently of graph traversal. Every serial Jac and GPU call checks
every score and visit count against that oracle; GPU calls also check status and
publication into the original walker objects. A [CPU-only test](tests.jac)
specifies a small worked example and compares the independent arithmetic oracle
with ordinary Jac traversal.

The reported question is when the **public GPU batch call** becomes faster than
ordinary serial Jac on the same graph and batch. Each case saves graph-building
time and runtime construction/PTX setup time separately. During each of three
warmup and 15 measured rounds, serial and GPU arms run in a seeded randomized
order with fresh walker state. The measured GPU interval is `run_walkers`, so it
includes packing, uploads, kernel execution, downloads, status handling, and
publishing results. It is not a pure kernel measurement. The measured serial
interval traverses the already built graph with fresh walkers. Constructing the
graph and initial walker objects is outside both intervals. Raw paired timings
and medians are saved in `results.json`; speedup is serial median divided by GPU
public-call median. Values below 1 indicate a GPU regression. The GPU runtime
remains open across rounds, so the setup cost is reported separately.

The benchmark is intentionally independent of the matrix-multiplication layout
suite. It measures application call costs and chain length effects; it does not
claim a random-versus-predicted node-layout comparison. See
[GPU runtime documentation](../../runtime.md) for the chain representation
and its supported Jac subset.

From the repository root, a future `plan` action prints the cases without
constructing graphs or using CUDA:

```bash
jac run --backend python scripts/gpu_walker/app_bench/sequence/benchmark.jac plan --output /tmp/jac-sequence-run
```

On a supported little-endian Linux NVIDIA machine with this checkout's working
Jac GPU runtime, an explicit `run` action executes the application benchmark:

```bash
jac run --backend python scripts/gpu_walker/app_bench/sequence/benchmark.jac run --output /tmp/jac-sequence-run
```

The output directory must be new and is never overwritten. **Neither command
was executed while adding this benchmark.** The test was also not executed.
There are no new measured results
in this change. The Jac compiler/runtime path and the GPU calls still need
validation on the intended NVIDIA host.
