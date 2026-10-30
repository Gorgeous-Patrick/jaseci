# What we expect from the Jac GPU compiler

The compiler should turn supported Jac walker programs into correct GPU kernels
and make useful use of information already present in the program, especially
graph traversal and cursor access order. The benchmark should establish whether
this produces faster kernels and whether those improvements survive the cost of
preparing and executing a real Jac workload.

This document summarizes the local `jaseci` checkout on `paper/jac-on-gpu`, commit
`8312acdd5`, reviewed on October 29, 2026. Existing requirements are linked below;
the proposed benchmark is a recommendation for the next experiment, not a claim
that an automatic optimizer or a performance target has already been delivered.

Implementation added October 30: the first documented matmul layout deliverable
now has a Jac benchmark, a [specification](scripts/gpu_walker/layout_bench/SPEC.md)
and a [teaching walkthrough and commands](scripts/gpu_walker/layout_bench/README.md).
It has not been run. The subtree application benchmark below remains a proposed
follow-up.

## 1. Compile the actual Jac program

For the supported GPU subset, the compiler must lower the selected Jac ability
and its traversal semantics through LLVM to executable NVIDIA PTX. Changing the
Jac ability must change the computation performed by the generated kernel.
Handwritten CUDA belongs in the comparison as a reference implementation.

The compiler must also emit an accurate interface description: parameter order,
field types, graph representation, private walker state, results, status outputs,
and required traversal bounds. The runtime uses this interface to pack and
transfer data and launch the kernel.

The current execution model assigns one independent walker to each GPU thread.
Walkers share read-only graph data and maintain private state. Serial Jac spawn
sequences are not automatically parallelized. Unsupported source constructs must
produce clear diagnostics rather than silently acquire different semantics.

Source: [GPU walker compiler documentation](scripts/gpu_walker/README.md).

## 2. Preserve correctness through every optimization

For inputs accepted by the GPU subset, compiled execution must preserve:

- The logical nodes, edges, query starts, and specified traversal order.
- Each walker's initial state, sequential state updates, and result position.
- Branch behavior, including short-circuit conditions and untaken arithmetic.
- Exact signed int64 arithmetic for the integer benchmarks, including values
  above the range that floating-point storage can represent exactly.
- Overflow, invalid-index, queue-capacity, and visit-bound checks and their
  observable failure behavior.
- Shared graph identity and read-only node data, even when walkers overlap.

Physical node IDs may change, but all field arrays, adjacency references, and
starting indices must be remapped consistently. Reordering storage must preserve
the logical sequence of visits. In the CSR subset, a repeated arrival executes
again; introducing a visited set would change the computation.

The compiler must retain the required status and result-write behavior. The
runtime is responsible for checking statuses before publishing results: a failed
batch must leave the original walker fields unchanged. Correctness checks should
compare every result with serial Jac and an independent oracle, and exercise
error cases separately. CPU LLVM checks alone do not establish GPU correctness.

Sources: [compiler semantics](scripts/gpu_walker/README.md),
[runtime and publication contract](scripts/gpu_walker/runtime.md), and
[subtree correctness evidence](scripts/gpu_walker/subtree_query/validation/20261021/REPORT.md#correctness-and-launch-audit).

## 3. Use traversal information to improve memory layout

The research question is whether Jac's known visit/cursor order can guide useful
physical placement of graph data. Nodes accessed together by neighboring GPU
threads may benefit from being stored near one another.

This involves both compiler analysis and runtime packing. The compiler can
provide access-order information; the packer must construct a consistent layout.
The existing layout experiments do not establish a general automatic layout
optimizer, and contiguous adjacency alone does not guarantee efficient accesses
across threads.

To test layout, hold the generated kernel fixed and compare random placement
with the proposed access-order placement. Preserve the same logical graph,
walker order, thread assignment, launch geometry, traversal bounds, and checks.
The current matmul contract specifically requires byte-identical checked LLVM O2
PTX for both Jac layouts. Its predicted layout concatenates complete cursor-a
discovery BFS followed by complete cursor-b discovery BFS, preserving first
occurrence. The documented subtree follow-up compares random and ordered-BFS
placement using an unchanged checked CSR kernel.

Source: [layout research contract](scripts/gpu_walker/layout_study/RESEARCH_CONTRACT.md).

## 4. Measure three separate questions

| Question | Controlled comparison | What the result establishes |
| --- | --- | --- |
| Does compiler optimization improve generated code? | Original Jac versus checked LLVM O2, with identical packed inputs, layout, traversal contract, and launch geometry | The effect of the compiler pipeline on this workload |
| Does access-order placement improve execution? | Random versus predicted layout using identical checked PTX | The effect of physical node layout |
| Does GPU execution help the application? | Serial CPU Jac versus the public GPU runtime on the same logical workload, with explicit timing boundaries | The practical benefit after runtime overhead |

Use the existing checked handwritten CSR kernel as a GPU reference for subtree
queries. A dense tiled CUDA matmul is a useful performance reference for matmul,
but its algorithm and data representation differ from graph traversal. The
entire remaining gap cannot be attributed to compiler code generation alone.

Kernel measurements should exclude compilation, packing, allocation, transfers,
and validation. Application measurements should include the work required to
deliver results to the caller. Report cold setup/compilation separately from
repeated calls, and identify whether graph construction is inside the interval.
The current public runtime repacks and uploads each batch even when it reuses
compiled code and allocations. A resident-buffer replay must therefore be
labeled separately from a public runtime call.

Warm up, repeat measurements, randomize comparison order, and retain distributions
and raw samples. Record GPU, compiler revision, toolchain versions, checks, input
hashes, and competing GPU activity. Report actual kernel duration separately from
CUDA graph event intervals that can include scheduling gaps. Hardware explanations
require supporting evidence; timing or modeled addresses alone do not measure
cache misses, transactions, or occupancy.

Sources: [required measurement boundaries](scripts/gpu_walker/runtime.md#general-graph-storage-experiment-2026-09-30),
[layout measurement contract](scripts/gpu_walker/layout_study/RESEARCH_CONTRACT.md), and
[subtree measurement boundaries](scripts/gpu_walker/subtree_query/validation/20261021/REPORT.md#measurement-boundary-and-shared-environment).

## 5. Proposed benchmark: batched subtree queries

A practical interpretation is hierarchical monitoring: sites contain buildings,
which contain devices. Each query chooses a subtree root and a threshold, then
counts qualifying readings, sums them, and reports whether any qualifying node
has an alert. Different queries share the same tree and may overlap.

This matches the existing `SubtreeQuery` program. Every query visits its full
subtree; the predicate changes accumulation, not traversal. The example assumes
a tree and does not deduplicate visits on general graphs.

Extend the [existing benchmark runner](scripts/gpu_walker/subtree_query/README.md)
with controlled CPU and public-runtime timing. Keep the existing kernel
comparisons. Sweep tree size, balanced versus irregular shape, depth, query batch
size, root versus leaf queries, and predicate selectivity. For the layout study,
add random versus ordered-BFS storage as a separate controlled comparison.

Report correctness, median latency and variation, queries per second, total node
visits, packing/reordering time, transfers, kernel time, and peak memory. Record
query-length distributions so a batch of leaf queries is distinguishable from a
batch of full-tree traversals. The main application result should identify the
workload sizes where GPU execution becomes faster than serial Jac, if it does.

Source: [subtree query semantics and runtime costs](jac/examples/gpu/subtree_query.md).

## 6. What counts as success

Correctness is mandatory. Performance is a measured outcome: improvement, parity,
and regression must all be reported. The reviewed contracts do not prescribe a
universal minimum speedup or require Jac to beat handwritten CUDA on every input.

The existing results illustrate why these distinctions matter:

- At 256-cubed matmul, predicted layout reduced the checked-O2 Jac kernel median
  from 947.380 to 540.418 microseconds, a 1.753x speedup. It remained 26.10x slower
  than the tiled CUDA reference and regressed on the two smallest shapes.
- Across 17 subtree workloads, production Jac and the checked handwritten CSR
  kernel had similar timings; checked LLVM O2 was usually slower. Enabling a
  standard optimization pipeline is therefore not evidence of an improvement.

These are saved measurements from a shared RTX 3090, not fresh measurements or
general guarantees. A useful next result would establish when layout helps real
graph queries and when the complete GPU path beats CPU execution, while retaining
the full correctness contract.

Sources: [matmul layout results](scripts/gpu_walker/layout_study/validation/20261022/REPORT.md),
[subtree results](scripts/gpu_walker/subtree_query/validation/20261021/REPORT.md), and
[paused subtree layout extension](scripts/gpu_walker/layout_study/validation/20261022/subtree/PAUSED.md).
