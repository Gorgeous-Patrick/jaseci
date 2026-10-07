# Named cursors on the GPU

GPU named cursors use the [Python arrival-barrier semantics](named-cursors.md).
A declaration fixes the number and names of channels at compile time; there is
no special two-channel ABI. Every lane has an independent FIFO for every cursor.
A round consumes one fresh arrival from every queue, holds all current positions
stable, tests the joint entry trigger, executes the ability once if it matches,
and appends visits to the selected queues. It ends when any queue is empty.
Mismatches consume that round without scanning ahead or executing visits.
Previously queued siblings can keep a channel moving when it does not visit.
Repeated starts and convergent arrivals remain distinct execution events.

```jac
walker Dot {
    cursor a, b;
    has total: int = 0;
    can multiply with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}
```

CPU launch: `{"a": left, "b": right} spawn Dot();`.
GPU host launch: `gpu.run_walkers([Dot(), ...], [bindings, ...], graph_format='csr')`.
Each binding has exactly the declared keys, with a node, node list or `None`.
The graph and walker instances must be private, live, in-memory objects.
Use separate instances for CPU and GPU comparisons.

## First GPU subset

One synchronous local joint entry ability, with the same explicit local node
trigger type for all channels, is supported. This restricts ability predicates,
not the declaration itself. Other plain node types can occur in initial queues
or graph rows: a type tag gates execution, so mismatching rounds perform no field
loads or visits. Node subclasses match with `isinstance`; their selected fields
must satisfy the compiled scalar/object schema. Node event callbacks, walker
inheritance, heterogeneous joint predicates, multiple abilities, dynamic cursor
selection, joint exits, async events and extra walker behavior are rejected.

The existing int64/float64/bool64 state and node field projections, checked
integer arithmetic, local variables, branches, dynamic `while`, `for/range`,
nested scalar loops and reports are reused. Nodes remain read-only on device;
walker fields and reports are published after the entire batch succeeds.
Each cursor may have zero or one implicit outgoing typed-edge visit per round.
A visit can be unconditional or be the sole statement of a simple `if` without
`else`. Its predicate is evaluated at its original statement position, including
state changes before that statement. Targets are appended after the ability;
positions remain stable and the one-visit-per-channel subset makes that delay
unobservable. Explicit query receivers, edge filters, visit insertion/else,
multiple visits to the same channel and visits in loops/general branches are
rejected. `break`, `continue`, `skip` and `disengage` are not in this GPU subset.
The existing scalar-loop restrictions still apply; no constant unrolling replaces
runtime loops.

Chain mode validates each selected relation for single successors and cycles.
CSR mode supports branches and cycles, bounded by queue capacity and maximum
round count. Both modes use ordered per-channel CSR in this ABI. Legacy walkers
retain their existing chain/CSR ABI and runtime path.

## Layout prediction versus execution

The host builds the reachable conservative relation closure, retaining Jac node
query neighbor order. Parallel edges to the same target use the query's existing
within-row node deduplication; convergent paths, repeated seeds and arrivals are
never deduplicated in execution queues.

For each cursor, BFS starts from the **entire batch** of seeds in lane order
(and seed-list order within a lane). Discovery uses an identity set and produces
a candidate node order. It does not concatenate complete paths per walker.
Candidates merge by discovery rank, then cursor declaration order. The first
occurrence of a shared identity wins; conflicting orders cannot all be honored.
Remaining identities retain conservative graph discovery order. This deterministic
heuristic is not an optimal layout algorithm and provides no guaranteed speedup.
Node storage is shared by identity, not by values; all heads and adjacency targets
are remapped to the resulting slots.

Conditional visits conservatively predict the declared relation even when a
predicate would stop execution. The device still evaluates the real predicate.
Prediction cannot alter correctness. `prediction_budget` limits expansions per
channel; identity discovery terminates cycles, and truncation records expanded
count, discovered count, budget and fallback. The full packed relation is retained
when the prediction budget is exhausted. `max_nodes` bounds graph collection;
exceeding that limit rejects packing rather than silently cutting execution.
Layout traversal is unique discovery; actual trajectories can repeat a node many
times. Neither discovery sets nor prediction budgets limit device arrivals.

`pack_cursors(..., layout='current'|'predicted'|'random', prediction_budget=...,
random_seed=...)` exposes the comparison strategies. `GpuWalkerRuntime.prepare`
uses prediction by default for named walkers. `buffers.prediction` records the
strategy, candidates, merge order and fallback. Current/random modes skip unused
BFS prediction. Host packing records collection, prediction, and SoA/remap costs
separately; SoA/remap includes field extraction and buffer construction.
`buffers.timings` records pack,
allocation, H2D, synchronized kernel launch and D2H costs. Kernel synchronization
timing includes launch and synchronization overhead; it is not a CUDA event timer.

## ABI and resources

The artifact format is `jac-ptx-cursors-v1`; the manifest lists exact typed argument
order, channels, triggers, edge relations and statuses. Node fields are SoA with
one copy per identity. Walker fields are field by lane. Heads/counts are cursor
by lane; scratch is `queue[(cursor * capacity + slot) * lanes + lane]`.
Each cursor has private current, reader, writer and pending count per lane.
Queue storage is bounded before allocation (default host budget 512 MiB).
Status codes distinguish invalid nodes/CSR rows, round exhaustion, queue capacity,
integer overflow/division and report capacity. A failing batch publishes no
walker state or reports. Each run uploads fresh seed queues.

## Examples and validation

`jac/examples/gpu/named_cursors.jac` includes dot, three cursors, conditional visits,
loops, reports and `build_matmul`. Every input and output node has one int `value`.
A row and B column chains are constructed once and shared by all output walkers;
there is no per-product input copy or coordinate-specific packer. GPU lanes compute
private totals; the host materializes those totals into the one-int output nodes.
Device-side writes to graph nodes are outside this implementation.

```bash
PYTHONPATH=jac python scripts/gpu_walker/test_named_cursors.py -v
JAC_GPU_TEST_CUDA=1 PYTHONPATH=jac python scripts/gpu_walker/test_named_cursors.py -v
```

The first command executes host LLVM JIT of the same device control flow and
compares it with real Jac CPU walkers. The second also launches actual CUDA PTX.
Mock driver tests validate the host ABI but cannot establish device correctness.
The layout comparison script records costs and evidence labels; do not infer an
acceleration from successful compilation or from host JIT/mock timings.

## Recorded device evidence

The [isolated layout and profiling report](gpu-cursor-layout-results.md) supersedes
the preliminary timing below. It retains seed distributions, actual layout hash
and identity-order audits, Nsight kernel/copy/API traces and CPU profiles. Nsight
Compute counter collection was denied; GPU bottleneck mechanisms remain an
explicit evidence gap.

The checked-in [RTX 3090 record](../../scripts/gpu_walker/validation/named_cursors_3090.json)
contains actual CUDA results for 32 by 32 integer matmul: 1,024 lanes, 2,048 shared
input nodes, one warmup round and five measured samples per layout. All outputs
matched the integer CPU oracle. Driver version, source hash, PTX hash, block size,
raw samples and all timing categories are recorded. Graph build cost was 33.903 ms.
Median costs in milliseconds:

| Layout | Pack | H2D | Kernel + sync | D2H | Pack through D2H |
| --- | ---: | ---: | ---: | ---: | ---: |
| Current | 30.814 | 0.105 | 0.0735 | 0.0261 | 31.952 |
| Predicted | 30.802 | 0.105 | 0.0746 | 0.0255 | 31.950 |
| Random | 31.363 | 0.103 | 0.0737 | 0.0260 | 32.611 |

These small samples do not establish a speedup. Kernel time includes launch and
synchronization overhead, packing dominates, and other CPU regression tests ran
concurrently. The comparison uses the same kernel and shared input graph for all
layouts. Current means conservative graph discovery order in the new packer;
all modes in that preliminary run computed prediction metadata, so those packing costs do not
compare against the old single-channel packer. Larger isolated experiments and device event/profiler timing would be
needed for a performance claim.

Validation also covered twelve named-cursor tests with real Jac CPU references,
LLVM host JIT, mock driver marshalling and optional actual CUDA, including real
seven-cursor and chain-mode launches. The complete host regression ran 92 tests
(90 passed, two device-only tests skipped in that invocation). Both skipped
matmul/report tests were subsequently run with CUDA enabled and passed. Thirteen
legacy integer/device-loop tests also passed with actual CUDA enabled. Repository
PTX/CPU tests ran eleven.
Mock and host JIT successes are distinct from the actual CUDA records above.
