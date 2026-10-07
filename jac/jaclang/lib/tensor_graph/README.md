# Tensor graph runtime (experimental)

Import this optional PyTorch-backed library with
`import from jaclang.lib.tensor_graph { TensorGraph, Compute, Input, Parameter, MatMul, Add }`.
It adds no dependency to the default `jaclang.lib` import.

```jac
import torch;
import from jaclang.lib.tensor_graph { TensorGraph, Compute, Input, Parameter, MatMul }

with entry {
    tg = TensorGraph(output_name="product");
    tg.add(Input(name="x"));
    tg.add(Parameter(name="weight", value=torch.eye(2, dtype=torch.float64)));
    tg.add(MatMul(name="product"), {"a": "x", "b": "weight"});
    feeds = {"x": torch.ones((1, 2), dtype=torch.float64)};
    result = tg.run(feeds);
    lowered = tg.compile(feeds, engine="fx");
    torch.testing.assert_close(result.output, lowered(feeds).output);
}
```

`runtime.jac` declares canonical primitive node types, `TensorEdge(port)`,
`TensorGraph`, and exactly one public `Compute` walker. `numerics.py` implements
architecture-independent metadata and lifetime helpers. `backend.py` performs
exact-class FX lowering and optional fullgraph Inductor execution.

The walker handles dependency readiness, metadata propagation/checks, traversal,
per-request state reset and final-use release. Select the result with
`output_name`; supply an exact dictionary of tensor-valued Input feeds.
`prepare` and numeric `run` spawn the same walker in distinct modes.
Direct `tg spawn Compute(values=feeds)` is also supported.

Operation semantics are explicit in each concrete Jac node's `ports`,
`attributes`, `infer` and `evaluate` methods, with inspectable versioned schemas
from `backend.schema`. The lowering accepts canonical class identity only;
subclasses, unregistered types and instance method overrides are rejected.
There is no string-kind execution dispatch or architecture-specific lowering.

The eager FX GraphModule aliases node-owned parameter/constant values through
buffer bindings. The guarded callable refreshes replacements with matching
metadata and rejects changed graph/attributes, input metadata or parameter
shape/dtype/device. Re-run `prepare` after metadata/topology edits, and re-lower
old executables. Inductor is optional (`engine="inductor"`), uses fullgraph,
static shapes and disables CUDA graphs; it does not silently fall back to eager.

This is inference-only library/runtime lowering, **not Jac compiler integration**.
No parser, compiler pass or shared runtime change is provided. Metadata supports
concrete shapes, float32/float64 math and rank >= 2 MatMul. Lifetime counts are
logical tensor references, not physical allocation or alias/buffer planning.
Captures deliberately retain intermediate values. Concurrent use of one mutable
graph is unsupported; use separate graph instances.

Full architecture, tests, reproducible commands and evidence:
[`transformer_runtime`](../../../examples/transformer_runtime/README.md).

## Lazy Cond (experimental)

`Cond` has exactly three graph ports: `condition`, `true_result`, and
`false_result`. The latter two edges name branch result **nodes**, not eagerly
computed values. `Greater(a, b)` is the registered floating comparison primitive;
its output is bool. Cond requires a rank-zero bool predicate on the same device
as branch outputs, whose concrete shape/dtype/device must match. The selected
result is returned as a contiguous clone (including identical branch roots).

`conditional.py` derives transitive slices C, T and F from validated real
producer edges, including each root. It precomputes C, T intersection F and their
dependency closure. All Input/Parameter/Constant leaves are explicit boundaries.
This is an intentional contract: **shared pure calculations execute before
condition selection**, even when only one branch will be selected. Exclusive
regions are T minus precomputed nodes and F minus precomputed nodes. Metadata
analysis checks both regions without running their numerical operations.

The same public Compute walker visits the precomputed region, reads the scalar
predicate, visits only the selected exclusive region, then the Cond join and
remaining downstream nodes. It routes tensor handles through the analyzed real
ports, resets state on every request and releases handles using selected-path
consumer counts. Python traversal uses `predicate.item()` once per Cond; CUDA
walker selection therefore synchronizes once. Static DAG liveness in reports
models both branches in metadata order, not a selected-path memory upper bound; conditional
execution records its actual releases separately. Diagnostic captures of
exclusive nodes are rejected because their values may not exist.

FX lowering extracts two GraphModules with placeholder operands, no captured
weights/buffers. Boundary values, including exclusive node-owned weights, are
explicit tensor operands of `torch.ops.higher_order.cond` (the higher-order
operator underlying `torch.cond`). Shared work remains in the outer FX graph;
exclusive numerical work remains inside branch modules. Fullgraph Inductor uses
this same graph. Eager FX may also read a device predicate through PyTorch's
higher-order dispatch; this API makes no asynchronous or performance guarantee.

First version: pure acyclic graphs with **one non-nested Cond**. Multiple/nested
Cond, a selected output independent of Cond, raw cycles, unknown exact types, missing/duplicate ports, incompatible
outputs, and exclusive values escaping their branch region are rejected. All
branch metadata must be valid, including the unselected branch. Value-dependent
errors (for example out-of-range Gather indices) can be safely skipped in an
unselected exclusive branch, but are not statically proven safe if selected.
Unrelated registered pure nodes run after the join. Shared work must itself be
safe, because the contract deliberately executes it before selection. This is
still library/runtime lowering, not a Jac compiler change.
