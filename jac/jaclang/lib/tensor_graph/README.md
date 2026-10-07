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
