# Bounded real-Jac large MatMul experiments

This experimental runner constructs actual `Scalar`, `RowNext`, and `ColumnNext`
objects from the compiled `named_cursors.jac` example. Input nodes are shared
across outputs. It runs the existing compiled `Dot` PTX, with int64 arithmetic;
it does not replace Jac traversal with dense matrix address arithmetic.

`run.py` executes **all M*N outputs** in row-major batches of at most 32768 lanes.
Each output becomes a real one-int Jac Scalar node within its bounded batch,
then is stored in an int64 binary artifact and released. It does not retain all
output nodes or all CPU walker objects simultaneously. Every GPU result and
status is checked. Structured weights A[i,k]=i+1, B[k,j]=j+1 allow independent
exact validation of every output as K*(i+1)*(j+1). A bounded test also compares
actual CPU Jac spawning against LLVM JIT on rectangular and boundary cases.

Layout planning uses N+(M-1) bindings: all columns of row zero, then the first
column of each remaining row. Their first-occurrence seed order equals that
of all M*N row-major output bindings, both per cursor and for combined graph
discovery. This compression applies only to layout discovery. Actual output
lanes, FIFO arrivals and kernel execution are not compressed. The regression
compares actual node identity order and all readonly arrays against full lanes.

Predicted explicitly budgets max(M*K,N*K) expansions and rejects truncated or
incomplete candidates. It concatenates the complete A BFS then complete B BFS.
`audit.py` independently rebuilds these sequences from Current CSR and verifies
the full binary identity order. Random permutes unified physical identities,
all columns, every CSR row/target and cursor heads through the existing shared
permutation implementation, preserving row order and lane order.

Queue capacity one is sufficient: each cursor starts with one seed, consumes
before appending at most one successor, hence its pending count never exceeds
one. Each real input chain has exactly K nodes and K-1 edges; the runner checks
outdegree <=1 and uses max_visits=K+1. This argument is specific to this fixture,
not a change to the generic branching cursor runtime.

The graph remains resident for all output batches within a layout. Only bindings
and private lane state are uploaded per batch. `Resident` implements the same
production PTX ABI with separate readonly and private allocations; the standard
runtime and existing OOM guards are unchanged. An explicit node admission limit,
RSS watchdog and 20 GiB available-memory reserve protect large experiments.
The watchdog terminates only its own experiment process upon violation.

Full-output runs are correctness/resource evidence, not paired performance
benchmarks. `replay.py` loads exact checksummed graph artifacts and samples the
same output batches for all layouts, with fixed seeds, shuffled paired order,
warmups and repetitions. These sampled runs are clearly labelled subset runs.
The first launch uses freshly uploaded bindings; the second replays resident
inputs without additional H2D. CUDA events can include CPU enqueue gaps.
Separate Nsight Systems runs provide actual kernel, copy and API intervals.
`analyze_profile.py` checks kernel identity, geometry and launch count before
attaching profiler durations. Nsight Compute is attempted without modifying
system permissions. Without counters, cache/coalescing/sector/DRAM/occupancy
causes must remain unestablished.

Example commands (set the Jac/LLVM environment for this checkout first):

```sh
env/bin/python scripts/gpu_walker/large_matmul/test_bounded.py
env/bin/python scripts/gpu_walker/large_matmul/run.py --shape 128x3000x128 --output /tmp/jac-large-pilot --seeds 928
env/bin/python scripts/gpu_walker/large_matmul/run.py --shape 3000x3000x3000 --max-input-nodes 18000000 --rss-budget-gib 48 --batch 32768 --cuda --output /tmp/jac-large-full
env/bin/python scripts/gpu_walker/large_matmul/audit.py /tmp/jac-large-full
env/bin/python scripts/gpu_walker/large_matmul/replay.py --inputs /tmp/jac-large-full --output /tmp/jac-large-events
```

Binary files use native-endian int64 (little-endian on the tested x86-64 host).
Reports contain dimensions, graph counts, pack count/timings, batches, coverage,
validation, hashes and source snapshots. Avoid interpreting pack wall as an
exclusive CPU baseline when concurrent CPU work is documented. Historical
reports from commit 145f9899f remain unchanged.
