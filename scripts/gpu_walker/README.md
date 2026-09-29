# Jac chain walkers to PTX

From the repository root, using this checkout's Jac compiler:

```bash
jac build jac/examples/gpu/chain.jac --as ptx --gpu-entry ChainSum -o dist/gpu
```

This emits `chain.ptx`, `chain.gpu.ll`, and `chain.ptx.json`. It does not run a GPU
kernel. The implementation is in `jaclang.compiler.backends.native.ptx_walker`,
written in Jac and using LLVM IRBuilder/NVPTX. It extracts an actual checked Jac
ability body; it does not substitute a handwritten sum kernel or generate C++.

To execute **actual Jac walker lists** on a GPU, use the new
[runtime launcher and memory allocation API](runtime.md). The example command is
`jac run jac/examples/gpu/chain_run.jac` on the NVIDIA server.

## Supported program

One node type with one numeric field, one empty edge type, one walker with one
private numeric field and one synchronous entry ability. The node and walker
fields must both be `float` (float64) or both `int` (signed int64).
The body contains one state update followed by one typed outgoing tail `visit`.
An update may be guarded by `if`/`elif`/`else`, with one update or nested `if`
per branch. A missing `else` leaves the state unchanged. Conditions support one
numeric comparison: `==`, `!=`, `<`, `<=`, `>`, or `>=`.

Assignments support `=`, `+=`, `-=`, and `*=`; expressions support `self`/`here`
field reads, matching numeric literals, unary signs, `+`, `-`, and `*`.
Integer walkers additionally support `%` and `%=` with Jac's signed modulo
semantics (for example, `-3 % 2 == 1`). Integer literals, inputs, and every
executed arithmetic intermediate must fit int64. Overflow and modulo by zero
produce per-lane error statuses; they never silently wrap or publish a partial
walker batch. Untaken branches do not execute their arithmetic.

For a complete example that sums even values while still traversing every node:

```bash
jac build jac/examples/gpu/even_chain.jac --as ptx --gpu-entry EvenSum -o dist/gpu
jac run jac/examples/gpu/even_chain_run.jac
```

The second command runs 1,000 actual walkers on CUDA and checks every result
against ordinary serial Jac. Integers remain integers throughout packing,
device execution and publication, including values above 2^53.

Inheritance, node abilities, helpers, shared writes, reports, branching graphs,
filtered/multi-hop queries, general loops, boolean combinations, mixed numeric
field types, and other effects are rejected with source locations. Standalone
scalar function exports still support only the separate float64/bool subset.

The entry point processes M independent instances of the selected walker type.
One thread performs a complete traversal. The graph is read-only and shared;
walkers may share nodes or suffixes, and retain independent starting states.
Serial Jac spawn sequences are not automatically parallelized.

## Packed device interface

The manifest records the actual node, edge, and field names. All parameters are
positional; arrays are contiguous and aligned for their element types:

| Parameter | Type | Length / meaning |
| --- | --- | --- |
| values | float64 or int64 pointer | N node values |
| next | int64 pointer | N successor indices; -1 ends a chain |
| heads | int64 pointer | M starting indices; -1 means no traversal |
| initial_total | float64 or int64 pointer | M initial private walker fields |
| results | float64 or int64 pointer | M final private fields |
| status | uint32 pointer | M completion codes |
| node_count | uint64 | N |
| walker_count | uint64 | M |

Input arrays must cover the counts. Results and status must be separate from
each other and all inputs. Use a 1D grid/block configuration that covers M
walkers; skip the launch for an empty batch. Inputs describe only the selected
node and edge types, with zero or one outgoing edge per node. The runtime object
packer validates types and edge multiplicity; PTX generation alone does not pack
live Jac objects. Node indices must fit signed 64-bit values.

Status 0 means success. Status 1 reports an invalid reachable head/successor.
Status 2 reports a cycle after at most N body iterations. Status 3 reports signed
integer overflow; status 4 reports integer modulo by zero. The manifest's
`scalar_dtype` and parameter dtypes identify the numeric storage type.
Failed lanes do not write results; the caller must inspect status before consuming them. This
runtime rejection defines the accepted finite-chain input domain, rather than
silently truncating a cyclic Jac walk. Threads beyond M touch no buffers.

Node order is arbitrary: move all fields together and remap next/heads. The
kernel follows next, including backwards and shared links. Reordering walker
slots requires moving heads/initial states together and restoring output order.
The verifier emits a four-walker Ours layout example, not an automatic layout
optimizer or a performance benchmark.

## CPU differential and compilation checks

```bash
python3 -B scripts/gpu_walker/verify.py \
  --shim /absolute/path/to/libjacllvm.so \
  --cache /tmp/jac-gpu-compiler-cache \
  --output /tmp/jac-chain-verification
```

The script emits device PTX and verifies LLVM IR. Separately, it lowers the
same selected ability and traversal loop for the host CPU with an explicit lane
index, invokes lanes sequentially in reverse order, and compares against **real
Jac graph construction and serial walker execution** in an isolated in-memory
context, without a database. This is not a GPU emulator.
Checks include distinct initial states, empty batches and traversals, 31/32/33
and 257/1024 walker batches, uneven chains, shared suffixes, random node/walker
permutations, signed zero, subnormals, infinities, NaN, bounds/cycles, and changed
Jac body arithmetic. Unsupported source variants must fail compilation.

`results.json` records the checks and `gpu_executed: false`.
`four_walkers.inputs.json` contains concrete packed inputs and serial reference
results for packed-array inspection. CPU checks cannot verify CUDA launch argument
packing, device execution, warp scheduling, or GPU numerical behavior.

The regular tests are `jac/tests/compiler/backends/native/test_ptx_walker.jac`.
Run them with the scalar PTX and CLI regression tests when changing shared code.

Integer arithmetic and publication tests are also included in
`jac/tests/runtimelib/test_gpu.jac`. On a CUDA server with this checkout's Python
environment, run the same integer tests on both CPU lowering and real CUDA:

```bash
PYTHONPATH=jac JAC_GPU_TEST_CUDA=1 python3 -B scripts/gpu_walker/test_integers.py
```

The suite compares against ordinary Jac, checks negative modulo and int64 limits,
tests skipped branches and arithmetic failures, and verifies exact publication
and whole-batch rollback. Without the environment variable it uses CPU lowering
and a CUDA driver double, so a GPU is not required by the regular test runner.
