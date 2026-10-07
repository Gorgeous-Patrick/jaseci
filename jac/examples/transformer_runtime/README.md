# Transformer built with the reusable tensor graph runtime

This sibling example preserves `transformer_graph/` and `transformer_dataflow/`.
It builds a one-layer encoder/decoder Transformer using canonical library nodes;
the model contains no execution walker, readiness queue, dependency checker, or
lifetime implementation. Parameters remain owned by `Parameter` nodes.

The reusable library lives at `jac/jaclang/lib/tensor_graph/`, alongside Jac's
existing `jaclang.lib` modules. Its optional PyTorch dependency is imported only
when this library is used. A narrow exception in `jac/.gitignore` exposes this
source subtree, which was otherwise hidden by the generic `lib/` build rule.

## Run

Use the provided environment, from the repository root:

```bash
XDG_CACHE_HOME=/tmp/jac-dataflow-cache /tmp/jac-dataflow-venv/bin/python -m jaclang run --backend python jac/examples/transformer_runtime/demo.jac
XDG_CACHE_HOME=/tmp/jac-dataflow-cache /tmp/jac-dataflow-venv/bin/python -m jaclang run --backend python jac/examples/transformer_runtime/validate.jac --device cpu --inductor
```

For an ordinary environment, use `python -m jaclang` with the current repository
Jac source and PyTorch 2.8.0 installed. The validation CLI omits Inductor unless
`--inductor` is passed; FX parity is always tested. Compilation is bounded to one
worker and uses `/tmp/jac-tensor-runtime-inductor` for its persistent cache.

After coordination releases the GPU, confirm there are no other compute jobs:

```bash
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
XDG_CACHE_HOME=/tmp/jac-dataflow-cache /tmp/jac-dataflow-venv/bin/python -m jaclang run --backend python jac/examples/transformer_runtime/validate.jac --device cuda:0 --inductor
```

No performance benchmark is part of this example. The tests use TF32=false,
CPU threads=1, inference mode, a fixed seed, and no dropout. Random weights
illustrate execution and do not provide trained language-model quality.

## Library API and semantics

`TensorGraph(output_name=...)` owns the graph's node registry and selected output.
Use `add(node, {port: producer_name})`, `wire`, `disconnect`, and `rewire` to change
actual Jac `TensorEdge(port=...)` connections. `prepare(feeds)` derives metadata,
topology and last uses; `run(feeds, capture=...)` executes through `Compute` and
returns `output`, optional `captured`, traversal and lifetime diagnostics.
Input feeds are an exact dictionary of tensor-valued `Input` names. The library
has no token vocabulary, encoder/decoder names or fixed layer order.

Canonical concrete types are:

| Type | Ports | Operation semantics |
|---|---|---|
| Input | none | supplied tensor feed |
| Parameter | none | persistent, node-owned parameter `value` |
| Constant | none | persistent, non-trainable tensor `value` |
| Gather | table, indices | `torch.index_select(table, axis, indices)` |
| MatMul | a, b | `torch.matmul(a, b)`, rank >= 2 |
| Add / Multiply / Subtract | a, b | floating tensor add / multiply / subtract |
| Square / Rsqrt / ReLU | x | square / reciprocal square root / ReLU |
| ReduceMean | x | mean over `axis`, with `keepdim` |
| Reshape | x | reshape to `dimensions` |
| Transpose | x | exchange `dim0`, `dim1` |
| Contiguous | x | explicit contiguous conversion |
| MaskedFill | x, mask | bool mask and `fill` |
| Softmax | x | softmax over `axis` |
| Arange | ref | int64 range of `ref.shape[axis]`, on `ref.device` |
| Full | ref | shape selected by `axes`, declared `dtype` and `fill` |
| Triu | x | upper triangle at `diagonal` |

Each exact Jac type declares its input ports, attributes, metadata checks and
PyTorch operation in its own methods. `Operation`, `Unary` and `Binary` are shared
abstract state/check layers and cannot be instantiated as supported primitives.
The lowering registry keys are the **exact canonical class objects**, not class
names, inheritance matches or a user `kind` string. Subclasses with the same name
are rejected. `backend.schema(node)` records qualified type, ports, attributes,
operation semantics and schema version for inspection and potential future
compiler recognition. Instance overrides of primitive methods are unsupported.

There is exactly one public walker, `Compute`. It runs a metadata pass when
`metadata_only=True` and a numeric pass otherwise. Both follow actual edges and
visit a consumer only after all input ports are ready. Numeric evaluation uses
polymorphic primitive methods, not the FX registry or a Transformer dispatcher.
The normal API spawns it through `prepare` and `run`; a direct `tg spawn
Compute(values=feeds)` uses the same library checks and execution path.

The library rejects missing/extra feeds, missing/duplicate/unknown ports, invalid
roots, unregistered consumers/types, cycles, incompatible broadcast/matmul,
dtype/device mismatch, illegal axis/reshape and non-bool masks. Metadata uses
concrete shapes and PyTorch meta tensors, without reading tensor values.
The plan fingerprint includes real edges, roots, exact type, operation attributes,
parameter/constant metadata and selected output. Shape or graph changes require
`prepare()` again; a stale FX executable requires lowering again. Same-metadata
parameter value replacement remains legal.

Consumer-port counts and last-use indices are derived from the actual graph and
walker order. Numeric `Compute` clears input inboxes and drops producer outputs
at their last consumption; weights/constants remain in their owning nodes and
the selected result remains live. Captures deliberately retain diagnostics.
Logical byte estimates count view aliases separately and are not allocator or
CUDA memory measurements. This is inference-only, with no autograd memory plan.

## Architecture and runtime lowering

`model.jac` only constructs the architecture. Its helper functions expand
embedding, attention, postnorm and FFN into library primitives; they do not run
forward computations. `initialization.py` initializes named parameters and the
fixed sinusoidal position table. The complete graph has an encoder self-attention,
decoder causal self-attention, encoder-memory K/V projections for cross-attention,
five expanded residual postnorms, two FFNs, output projection and softmax.
The target is shifted: labels `[6,7,2]` use input `[BOS=1,6,7]`.

`graph.compile(feeds, engine="fx", capture=...)` converts the validated actual Jac
graph into a `torch.fx.GraphModule`. Producer inputs come from the plan's real
port-to-producer mapping, and canonical classes lower to explicit tensor ops.
`Arange`/`Full` retain shape/device dependencies on their producer, rather than
substituting a hand-authored shape table. Every Jac primitive's FX value carries
its qualified semantic schema and inferred metadata. FX source and DOT exports
come from the constructed graph.

The GraphModule's buffers alias the source Jac `Parameter`/`Constant` tensors;
these are bindings rather than a new model weight snapshot. The guarded callable
refreshes those bindings when `Parameter.value` is replaced with identical
metadata. It rejects changed topology/attributes, dtype/device/shape and input
metadata. It supports distinct input values and explicit captures.

`engine="inductor"` applies `torch.compile` to that GraphModule, using the actual
Inductor backend, `fullgraph=True`, `dynamic=False`, and CUDA graphs disabled.
Unsupported compilation is reported explicitly, never presented as an eager
success. Numerical parity failure is a test failure. FX/Inductor numeric execution
runs the lowered graph rather than a numeric walker traversal; `Compute` was used
to validate and plan the Jac graph before lowering. Lowered execution has its own
PyTorch lifetime handling, not a claim that Jac's release trace executes there.

This is **library/runtime lowering, not Jac compiler integration**. No Jac parser,
compiler pass, optimizer, code generator or shared runtime file is modified. The
explicit canonical type semantics provide a future recognition contract, but no
compiler currently consumes this contract as part of this work. This is operation
IR, comparable in level to FX and tensor export graphs; it is manually constructed
rather than captured from a Python program. There is no Dynamo/Inductor speed claim.

## Tests and saved evidence

`reference.py` is an independent direct PyTorch Transformer equation pipeline. It
reads cloned node-owned parameter values and never invokes this library's graph
executor or lowering. Validation checks 137 attention/projection/norm/FFN/output
intermediates, causal masking and future-token isolation, encoder influence,
normalization, three additional input-length pairs, repeated inputs, retained old
results, parameter replacement and graph mutation.

Residual skip rewiring changes the Jac graph and corresponding reference; old FX
executables reject it, newly lowered FX/Inductor match. Inserting a Constant and
Multiply changes the actual output path without changing `Compute`. Missing
encoder memory input and illegal metadata/dependencies are rejected by library
checks. A separate five-node matrix graph uses different inputs/output names to
prove library reuse outside the Transformer architecture.

`results/validation_cpu.json` and `validation_cuda_0.json` contain compact test
results. Small float64 DOT, generated FX source, semantic schemas and liveness
plans are saved for the original and rewired graph. `preservation.json` records
all files in both previous examples; validation compares their SHA-256 and file
sets without importing or modifying those directories.

Completed validation on 2026-10-07, with PyTorch 2.8.0+cu128, Python 3.12.11,
CUDA 12.8, and an RTX 3090 (driver 580.65.06). The GPU process check was empty
before CUDA testing; its correctness window has been released. All commands
above completed with exit status 0.

- CPU and CUDA: small d=8/h=2/FF=16/V=13 with source/target 4/3, and medium
  d=64/h=4/FF=128/V=127 with source/target 32/24, each float64 and float32.
- All eight original cases passed walker, independent reference, FX, and actual
  fullgraph Inductor execution, including repeated compiled calls.
- Small float64 rewired graphs passed Inductor on both CPU and CUDA. Other rewired
  configurations passed walker/reference/FX but were not requested for Inductor.
- All 19 invalid-dependency/type/metadata cases were rejected on each validation
  invocation. Five-node non-Transformer reuse, three additional length pairs,
  ten parameter replacements, state isolation and runtime/FX resident-forward
  audits passed. Actual insertion produced 202 nodes and 226 tensor edges.
- Direct public `Compute` spawning on an unprepared Transformer graph passed the
  CPU demo, including automatic metadata planning and FX output parity.
- All 80 files of transformer_graph and all 74 files of transformer_dataflow
  have unchanged file sets and SHA-256, including their existing results/docs.

| device | config / dtype | walker / FX vs reference max abs | Inductor vs reference max abs |
|---|---|---:|---:|
| cpu | small_float64 | 0 | 2.6645e-15 |
| cpu | small_float32 | 2.861e-06 | 1.6689e-06 |
| cpu | medium_float64 | 0 | 1.5987e-14 |
| cpu | medium_float32 | 6.6757e-06 | 5.722e-06 |
| cuda_0 | small_float64 | 0 | 4.4409e-15 |
| cuda_0 | small_float32 | 1.1921e-06 | 1.9073e-06 |
| cuda_0 | medium_float64 | 1.2434e-14 | 1.199e-14 |
| cuda_0 | medium_float32 | 8.5831e-06 | 6.0797e-06 |

These are correctness errors, not timings. FX also matches the walker output;
the table compares both paths with the independent reference. Float32 reference
positions are recomputed on the target device/dtype, whereas the constructed
position table is initialized in CPU float64 and converted, so float32 agreement
is tolerance-based rather than bitwise. Tolerances are float64
atol=2e-11/rtol=2e-10 and float32 atol=3e-5/rtol=3e-4. The causal masked scores have
expected -inf; other checked intermediates and probabilities are finite.

Inductor reported reduction-strategy and disabled-TF32 advisory messages on
CUDA; the tests retained TF32=false and passed without backend fallback.
The compiled graphs return diagnostic captures, so these tests do not represent
an optimized production-output-only benchmark. No speed claim is made.

Rebuild the compact summary and repeat the preservation check without GPU work:

```bash
/tmp/jac-dataflow-venv/bin/python jac/examples/transformer_runtime/summarize.py
```


Limits: one encoder/decoder layer, batch=1, float64/float32, concrete shapes and
fixed positional-table capacity; no training, padding mask, symbolic constraints,
KV cache, in-place/alias analysis or portable executable serialization. The FX
callable is tied to the live owning graph and metadata signature. Concurrent use
of the same mutable graph is unsupported; use distinct instances. Captures retain
intermediates and are intended for correctness, not a production throughput claim.
