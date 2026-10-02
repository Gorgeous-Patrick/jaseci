# Launching actual Jac walkers on CUDA

The experimental API takes actual walker objects and their starting nodes. It
compiles the selected walker class once, packs the reachable graph, launches a
batch, and writes successful final scalar states back to the same walker objects.

```jac
import from jaclang.runtime.gpu { GpuWalkerRuntime }

with GpuWalkerRuntime(ChainSum, device=0) as gpu {
    result = gpu.run_walkers(walkers, starts);
    print(result.values);
}
```

`walkers` contains distinct instances of the same compiled class. `starts[i]` is
the starting node for `walkers[i]`; `None` means an empty traversal. Outputs stay
in input order. The graph is shared and read-only. The one-shot convenience
function `run_walkers(walkers, starts, device=0)` creates and closes a runtime for
one batch; use the context manager to reuse the compiled kernel and allocations.

From a checkout running this version of Jac on the GPU server:

```bash
jac run jac/examples/gpu/chain_run.jac
```

The example constructs 3,000 real Jac nodes and 1,000 `ChainSum` instances, with
one three-node chain per walker. It prints the batch size, allocation size, GPU
name and first/last five results, and checks every result and updated walker
field against `19 * i + 6`. The first five totals are
`[6.0, 25.0, 44.0, 63.0, 82.0]`; the last is `18987.0`. Change `walker_count` in
the example to try a different batch size. This command performs GPU execution.
It fails if CUDA is unavailable; it does not substitute CPU execution.

For signed integer nodes and an integer walker state, run
`jac run jac/examples/gpu/even_chain_run.jac`. Its `EvenSum` ability uses
`if here.value % 2 == 0 { self.total += here.value; }` before the same tail
`visit`. All 1,000 GPU results are checked against serial Jac walkers.
Numeric node and state fields must have the same numeric type; boolean fields may coexist. Integer values are stored
as signed int64 throughout; input values outside that range are rejected, as are
floats and booleans in integer fields. Integer arithmetic overflow raises
`OverflowError`; integer modulo by zero raises `ZeroDivisionError`. Neither
failure publishes any walker fields, including lanes that otherwise succeeded.

The host runtime is implemented in Jac using standard-library ctypes to call the
CUDA Driver API. The server needs little-endian 64-bit Linux, an accessible
NVIDIA driver, and compute capability 7.0 or newer. The Jac compiler's LLVM shim
must include NVPTX. It does not require CuPy, NVRTC, nvcc or an additional Python
environment. The driver JIT-loads the emitted PTX using
[`cuModuleLoadDataEx`](https://docs.nvidia.com/cuda/cuda-driver-api/cuda_driver_api/group__CUDA__MODULE.html).

## Chain memory allocation

Let N be the number of distinct reachable nodes, M the number of walkers, F
the number of numeric node leaf fields, and S the number of walker leaf fields
(including flattened nested fields).
Only scalar data and dense integer indices are copied to the GPU, never host
object pointers. Shared nodes and shared suffixes occupy one physical slot.

| Allocation | Arrays | Active payload |
| --- | --- | --- |
| Graph arena | F columns of `scalar[N]`, `next: int64[N]` | 8 (F + 1) N bytes |
| Walker arena | `heads: int64[M]`, S initial and S result columns of `scalar[M]`, `status: uint32[M]` | (12 + 16 S) M bytes |

`scalar` is float64 or signed int64, as specified by the compiled schema. Both
use eight bytes, so integer walkers use the same arena sizing and alignment.

Each arena is one `cuMemAlloc` allocation subdivided into SoA arrays. Every array
starts at a 256-byte offset. Node and walker capacities grow independently to
powers of two; smaller later batches retain those capacities. The memory plan
reports both active payload and allocated arena sizes. It excludes the driver's
context, JIT module and any per-thread spill storage.

```text
Graph arena:   field_0[G] | padding | field_1[G] | ... | next[G] | padding
Walker arena:  heads[W] | padding | initial_0[W] | ... | initial_S-1[W]
               results_0[W] | ... | results_S-1[W] | padding | status[W]
```

G and W are retained capacities, while the kernel receives the actual N and M.
The original single-field 1,000-walker example has 76,000 payload bytes and initially reserves
94,208 arena bytes (65,536 graph bytes plus 28,672 walker bytes), with capacity
for 4,096 nodes and 1,024 walkers. There is no allocation per node, edge, walker
or hop on the device. A thread holds its current node index and all state fields
privately.

Arena growth allocates a replacement before releasing the old allocation. Peak
memory during growth includes both; the runtime checks currently free device
memory and also handles driver allocation failures. There is no paging or
automatic chunking if the batch does not fit. `close()` or leaving the `with`
block releases both arenas, the module and the owned CUDA context. Calls restore
the caller's prior CUDA context.

Every batch is repacked and reuploaded. Allocation reuse does not imply that
node values, topology or walker initial states are cached. This supports changes
between synchronous calls without stale GPU data. Keep the input objects stable
during a call. The runtime is confined to its creating host thread.

## Node order

The packer assigns slots to starting nodes in walker-list order, then discovers
their successors in the same order, skipping nodes already assigned a slot.
For four disjoint chains this gives:

```text
A0 B0 C0 D0 | A1 B1 C1 D1 | A2 B2 C2 D2
```

This is the Ours layout for that example. Overlapping paths use first discovery
and retain one slot per node; this is not a general optimal-layout claim. All
successor indices and heads are remapped. The kernel still follows next rather
than assuming a stride. The packer processes each included node once and maps M
starts; it also examines incident adjacency to find selected edges. Packing does
not execute abilities or precompute results.

`gpu.prepare(walkers, starts)` returns an inspectable `PackedWalkerBatch` without
loading a CUDA driver or allocating VRAM. Its `memory_plan()` describes an
initial allocation. `result.memory` describes the allocation used by an actual
call, including capacity retained from prior batches. `run_walkers` always packs
fresh inputs, even if `prepare` was called separately.

## Multiple node fields and nested data (2026-10-01)

Node attributes use SoA: each numeric leaf has its own contiguous, 256-byte
aligned column. A node with `value`, `weight`, and `position: Position`, where
`Position` has `x` and `y`, produces columns in declaration order:

```text
value:      [v0 v1 v2 ...]
weight:     [w0 w1 w2 ...]
position.x: [x0 x1 x2 ...]
position.y: [y0 y1 y2 ...]
```

`here.position.x` lowers to a direct column lookup using the current node ID.
Nested objects have no GPU allocation or device pointer chain. Fixed local
`obj` structures may nest further; recursive types, containers, optional fields,
inheritance, accessors and object behavior are rejected. All numeric leaves
must currently match the walker state's int64 or float64 type. Walker fields
use the same projection, with the private update rules described below.

Nested attribute objects belong to a single node. Packing checks exact object
types and rejects an object identity owned by two distinct nodes in the packed
reachable graph, including sharing below different parent objects. Multiple
walkers can share the same node. Graph convergence remains supported by CSR.
The host graph and all nested data must remain stable during a batch. Between
calls, every field is repacked, so changes to nested values are uploaded too.

The packer currently uploads all declared numeric leaf columns, including
unused fields. `gpu.schema.field_paths()` lists column names;
`gpu.prepare(walkers, starts).buffers.columns()` exposes the host arrays in
the same order. All columns share the same node permutation. Reordering must
also remap adjacency and starting IDs without changing logical query order.

Multi-field kernels use v2 manifests with a `field_path` for each leading
column pointer. Column pointers are followed by the existing topology, walker,
scratch and count parameters. The CUDA session validates the compiled field
count and column sizes before launch. Single-field v1 argument lists remain
compatible. `GpuMemoryPlan.node_field_count` includes flattened leaves and
accounts for their payload, padding and retained capacity.

SoA is the first implementation choice for multi-field experiments. Adjacent
threads reading the same column can benefit when node IDs are nearby; this does
not guarantee coalescing for scattered traversal. AoS or grouped layouts may
be compared later. This change provides no measured speedup claim.

```bash
jac build jac/examples/gpu/multi_field.jac --as ptx --gpu-entry WeightedSum --gpu-graph-format csr -o dist/gpu-fields
jac run jac/examples/gpu/multi_field_run.jac
```

## Multiple walker fields (2026-10-01)

Walker state also uses SoA. For `total`, `count`, and `metrics: Metrics` with
`weighted` and `last` numeric leaves, the runtime packs four initial columns:

```text
total:            [walker0.total            walker1.total            ...]
count:            [walker0.count            walker1.count            ...]
metrics.weighted: [walker0.metrics.weighted walker1.metrics.weighted ...]
metrics.last:     [walker0.metrics.last     walker1.metrics.last     ...]
```

There are four matching result columns. Adjacent lanes load adjacent initial
values; during traversal each thread maintains its own current values, then
stores all results on success. Sequential updates and multiple assignments
within branches preserve Jac statement order, so a later expression sees
earlier updates to other fields. An untaken branch leaves its fields unchanged.
More fields can increase register use; this change makes no performance claim.

`gpu.schema.state_paths()` lists state columns in declaration order.
`batch.buffers.initial_columns()` and `result_columns()` expose their host
arrays. After execution, `result.fields` maps every leaf path to its output
column. `result.values` remains the first state column for compatibility.
`result.memory.state_field_count` accounts for all flattened walker leaves.

Numeric node and walker leaves share int64 or float64; boolean leaves may coexist. Fixed nested objects are supported to multiple levels. A mutable
walker attribute object must belong to exactly one state path in one walker:
sharing between walkers, aliasing between paths in one walker, and sharing with
graph nodes are rejected before launch. Packing retains nested object identities;
copyback verifies those identities and every initial numeric value before
writing any field. Driver errors, a failing lane, or changed host state prevent
the whole batch from publishing. Nested objects retain their host identity;
only numeric leaves are updated. Keep all inputs stable during a call.

```bash
jac run jac/examples/gpu/walker_fields_run.jac
```

The example uses a shared branching CSR graph and checks all four state fields
for 1,000 walkers against serial Jac. Its v3 manifest contains a separate initial
and result pointer for every leaf. Single-state v1/v2 kernels retain their ABI.
Top-level numeric defaults must be finite matching literals; nested defaults
are not inferred from constructors. The runtime always uses actual instance
values, including constructor overrides.

## Semantics and current limits

The accepted walker source is the restricted chain subset described in
[README.md](README.md). Runtime objects must be private, live, in-memory instances
of the exact declared classes. Persisted/owned/access-controlled graphs,
heterogeneous walker lists, duplicate walker instances and undirected selected
edges are rejected before CUDA allocation. The default `graph_format="chain"`
also rejects branching selected edges and cycles. The experimental CSR option
below accepts branching adjacency and bounds traversal on cyclic graphs.

This API executes the selected numerical traversal. It updates the declared
walker state fields, and does not generate ordinary spawn path records. Numeric
reports are supported as described below.
Walkers with an active traversal, pending visits, ignores, disengagement, or prior
path records are rejected. Repeated GPU batches can reuse completed
walker instances and their updated scalar fields.

Copyback occurs only after synchronization and after every lane reports success.
A kernel error or nonzero lane status does not publish any walker state. Changed
host walker state is checked before publication. This is not a general concurrent
host-object transaction; callers must keep the batch stable during the call.
CUDA API failures close the device session; create a new runtime before retrying.

The loaded class must come from its available, current `.jac` source file. The
runtime checks source identity when prepared and rejects later source/dispatch
changes. Reload edited modules and recreate the runtime. Sealed sources and
dynamic monkey-patching are outside this prototype.

## General-graph storage experiment (2026-09-30)

**Decision: try CSR for the first general-graph prototype. This is one
experimental storage choice and may be revised or replaced after measurement.**
The CSR path is now implemented alongside the original `next[]` chain path.
Select it explicitly; the default remains `graph_format="chain"` so previous
experiments retain their storage and execution path.

```jac
with GpuWalkerRuntime(
    GraphSum, graph_format="csr", queue_capacity=1024, max_visits=1000000
) as gpu {
    result = gpu.run_walkers(walkers, starts);
}
```

The convenience function accepts the same options:
`run_walkers(walkers, starts, graph_format="csr", queue_capacity=1024,
max_visits=1000000)`. Queue capacity and the visit limit are positive per-walker
bounds, not preview windows. A finite DAG may require more visits than nodes
because arrivals through different paths execute the ability again.

Run the 1,000-walker branching/shared-graph example on an NVIDIA server:

```bash
jac run jac/examples/gpu/csr_graph_run.jac
```

It checks every sum against ordinary serial Jac and uses a second walker whose
order-sensitive checksum must be `12344555`. This is a correctness example,
not a performance benchmark.

The research goal is to test whether information available from Jac walker
semantics can improve physical node ordering on the GPU. General graphs are
required for that evaluation; linked lists are an initial validation case.
CSR provides a storage baseline and is not itself the proposed contribution.

The first experiment retains fixed topology and read-only graph data. It uses
`offsets[N + 1]` and `targets[E]` for adjacency, with node fields in separate
dense arrays and private walker state stored separately. E counts entries in
the selected typed node-query projection, rather than every edge in the Jac
graph. Parallel edges to the same neighbor produce one entry in that row,
matching `visit [->:Link:->]`; first-occurrence order is preserved. The original
Jac graph and its edge objects remain intact. Physical node permutation must
remap node fields, adjacency rows, target indices, and walker starting indices
without changing the logical order within each row.

Each thread executes an ability, then appends its neighbors to a private FIFO
ring queue. There is no global visited set: a shared node reached twice executes
twice. Cycles are represented in CSR, but this subset's unconditional tail visit
cannot finish a reachable cycle. Exceeding `max_visits` returns status 2; exceeding
`queue_capacity` returns status 6. Both prevent publication of the entire batch.
Invalid reachable row offsets return status 5. Invalid nodes and integer faults
retain statuses 1, 3 and 4. Failed lanes leave result slots untouched.

The CUDA session reuses four independently growing, aligned arenas:

| Arena | Arrays / element types | Active bytes |
| --- | --- | --- |
| Nodes | F columns of `scalar[N]`, `offsets[N + 1]: int64` | `8(F + 1)N + 8` |
| Edges | `targets[E]: int64` | `8E` |
| Walkers | heads, S initial columns, S result columns, status | `(12 + 16S)M` |
| Queues | `queue[Q * M]: int64`, Q = queue_capacity | `8QM` |

The queue uses `queue[slot * M + lane]` so adjacent lanes' equal queue positions
are adjacent in memory. It is device scratch: no host queue is uploaded or
downloaded. Queue counters and current state fields are thread-private.
Payload is `8(F + 1)N + 8 + 8E + (12 + 16S)M + 8QM` bytes before alignment and capacity rounding.
There is no allocation or host-driven kernel launch per hop. Queue storage can
dominate small graphs, so measure its cost and tune Q for the workload.

The implementation keeps one thread per walker. A contiguous adjacency
list does not guarantee coalescing across threads visiting different nodes.
Measure reads of row offsets, edge targets, and node fields separately where
profiling permits: degree variation, dependent address loads, and divergent
traversals may reduce or hide the benefit of improved node placement.

Compare layouts using the same logical graph, walker inputs, traversal order,
kernel, and thread assignment. Record kernel time and memory-access behavior,
plus analysis, packing/reordering, transfer, and end-to-end costs. Retain CSR
only as an experimental choice; evidence of an adjacency bottleneck can justify
trying a different representation in a separate comparison. No performance
benefit or optimality is assumed in advance.

CSR uses the same restricted scalar ability body as the chain
backend: boolean leaves alongside matching numeric node and private walker leaves, one synchronous
entry ability, and one outgoing typed tail visit. Node writes, filtered queries,
arbitrary visit control, object reports, and heterogeneous graphs remain unsupported.

## Verification boundary

`jac test jac/tests/runtimelib/test_gpu.jac` runs host-only regression tests with
real Jac objects. A C-callable driver double checks 64-bit parameter marshalling,
aligned arena offsets, allocation reuse/growth, context restoration, cleanup,
empty batches and failure-before-copyback behavior. Its launch callback invokes
CPU LLVM lowering; it does not interpret or execute PTX.

GPU correctness must be checked by running `chain_run.jac` on the NVIDIA server.
The tiny example is a correctness check, not a throughput or speedup benchmark.

`test_gpu.jac` also runs the CSR suite in `scripts/gpu_walker/test_csr.py`. It
compares actual serial Jac, CPU LLVM lowering, and the CUDA host ABI through a
driver double. On a CUDA server, execute the same suite with real PTX:

```bash
PYTHONPATH=jac JAC_GPU_TEST_CUDA=1 python3 -B scripts/gpu_walker/test_csr.py -v
```

Coverage includes FIFO order and repeated arrivals, parallel-edge node-query
deduplication, random DAGs and physical permutations, 0/1/31/32/33/257/1000 walker
batches, high degree, empty rows, ring wrap, cycles, bounds and arithmetic
failures, batch rollback, allocation reuse and cleanup. Without the environment
variable, the suite does not execute PTX on a GPU.

## Numeric reports

Both graph formats support `report` of numeric expressions matching the
walker's scalar type (`int64` or `float64`). Reports can appear between
assignments and inside supported conditionals. Each report captures its value
at that statement; repeated arrivals emit again in traversal order.

```jac
with GpuWalkerRuntime(
    Collector, graph_format="csr", report_capacity=1024
) as gpu {
    result = gpu.run_walkers(walkers, starts);
    print(walkers[0].reports);
    print(result.reports);
}
```

`report_capacity` is a positive per-walker bound, independent of the visit
queue and visit limit. A separate aligned arena holds `report_counts[M]` and
`report_values[report_capacity * M]`. The physical index is
`slot * M + lane`: the first reports of adjacent walkers are adjacent.
Payload storage requires `8 * M * (report_capacity + 1)` bytes. No report arena
is allocated for walkers without report statements. Device execution resets
each active lane's count; unused value slots have no meaning.

Report-enabled kernels use v4 manifests, appending the counts pointer, values
pointer, and report capacity after the existing arguments. Non-report kernels
retain their previous ABI. Status 7 indicates report capacity overflow. An
arithmetic, traversal, CUDA, or report-capacity failure publishes neither state
nor reports for any walker. Successful completion replaces each walker's
reports, including clearing them after an empty traversal. Existing report lists
are accepted when preparing a new batch. `result.reports` contains one list per
walker in input order. This batch API does not enqueue reports into a server
request or implement nested-spawn report propagation.

Object, string, and container reports remain unsupported. Boolean and numeric reports may share a stream. Run the
GPU example with `jac run jac/examples/gpu/reports_run.jac`. Host regression
coverage lives in `scripts/gpu_walker/test_reports.py`; set
`JAC_GPU_TEST_CUDA=1` to enable its additional real-device check.

## Boolean fields and reports

Node and private walker leaves accept `bool`, including nested object fields.
Host inputs must be actual booleans. Each boolean leaf occupies an aligned SoA
column of canonical 64-bit 0/1 values; device expressions use predicates.
Assignments, equality comparisons, `not`, and short-circuit `and`/`or` preserve
boolean semantics. Boolean fields can accompany one numeric field type.

Kernels using boolean fields or tagged reports emit v5 manifests with per-field
dtypes. A report stream containing booleans uses uint64 payloads plus uint64
tags: 1 means bool, 2 means signed int64, and 3 means float64 bits. Both arrays
use `slot * walker_count + lane`, so adjacent walkers' first reports remain
adjacent. The tag pointer follows the report capacity argument. Payload storage
requires `8 * M * (1 + 2 * report_capacity)` bytes. Host decoding preserves
`True` versus `1` and exact integer precision. Invalid tags or noncanonical
boolean outputs prevent publication of the whole batch. Homogeneous numeric
streams retain the earlier report ABI.

Run `jac run jac/examples/gpu/booleans_run.jac` for a 1000-walker CSR comparison
against serial Jac. Set `JAC_GPU_TEST_CUDA=1` when running
`scripts/gpu_walker/test_booleans.py` to exercise real CUDA.
