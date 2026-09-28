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

The host runtime is implemented in Jac using standard-library ctypes to call the
CUDA Driver API. The server needs little-endian 64-bit Linux, an accessible
NVIDIA driver, and compute capability 7.0 or newer. The Jac compiler's LLVM shim
must include NVPTX. It does not require CuPy, NVRTC, nvcc or an additional Python
environment. The driver JIT-loads the emitted PTX using
[`cuModuleLoadDataEx`](https://docs.nvidia.com/cuda/cuda-driver-api/cuda_driver_api/group__CUDA__MODULE.html).

## Memory allocation

Let N be the number of distinct reachable nodes and M the number of walkers.
Only scalar data and dense integer indices are copied to the GPU, never host
object pointers. Shared nodes and shared suffixes occupy one physical slot.

| Allocation | Arrays | Active payload |
| --- | --- | --- |
| Graph arena | `values: float64[N]`, `next: int64[N]` | 16 N bytes |
| Walker arena | `heads: int64[M]`, `initial: float64[M]`, `results: float64[M]`, `status: uint32[M]` | 28 M bytes |

Each arena is one `cuMemAlloc` allocation subdivided into SoA arrays. Every array
starts at a 256-byte offset. Node and walker capacities grow independently to
powers of two; smaller later batches retain those capacities. The memory plan
reports both active payload and allocated arena sizes. It excludes the driver's
context, JIT module and any per-thread spill storage.

```text
Graph arena:   values[G] | padding | next[G] | padding
Walker arena:  heads[W]  | padding | initial[W] | padding
               results[W] | padding | status[W] | padding
```

G and W are retained capacities, while the kernel receives the actual N and M.
The default 1,000-walker example has 76,000 payload bytes and initially reserves
94,208 arena bytes (65,536 graph bytes plus 28,672 walker bytes), with capacity
for 4,096 nodes and 1,024 walkers. There is no allocation per node, edge, walker
or hop on the device. A thread holds its current node index and scalar state
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

## Semantics and current limits

The accepted walker source is the restricted chain subset described in
[README.md](README.md). Runtime objects must be private, live, in-memory instances
of the exact declared classes. Persisted/owned/access-controlled graphs,
heterogeneous walker lists, duplicate walker instances, branching selected edges,
undirected selected edges and cycles are rejected before CUDA allocation.

This API executes the selected numerical traversal. It updates the declared
walker state field, and does not generate ordinary spawn path records or reports.
Walkers with an active traversal, pending visits, ignores, disengagement, prior
path records or reports are rejected. Repeated GPU batches can reuse completed
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

## Verification boundary

`jac test jac/tests/runtimelib/test_gpu.jac` runs host-only regression tests with
real Jac objects. A C-callable driver double checks 64-bit parameter marshalling,
aligned arena offsets, allocation reuse/growth, context restoration, cleanup,
empty batches and failure-before-copyback behavior. Its launch callback invokes
CPU LLVM lowering; it does not interpret or execute PTX.

GPU correctness must be checked by running `chain_run.jac` on the NVIDIA server.
The tiny example is a correctness check, not a throughput or speedup benchmark.
