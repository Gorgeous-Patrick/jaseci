# Can a Jac compiler pass run on a GPU?

Static architecture review, 2026-11-01. No compiler pass or GPU workload was run for this review.

## Short answer

**A subset of a pass is technically plausible, but this checkout does not execute
the compiler itself on a GPU.** Jac's AST uses Object-Spatial Programming (OSP):
AST classes are graph nodes, and child/role relationships are edges
([architecture](../../jac/jaclang/cli/docs/internals/compiler_architecture.md#the-tree-is-a-graph),
[node definition](../../jac/jaclang/compiler/frontend/unitree.jac#L154)). That gives
some independent node checks a natural parallel unit. It does not make the
current compiler graph directly usable as device memory.

The existing PTX path compiles **application walkers** with restricted scalar
fields and read-only graphs; it does not offload a compiler pass
([supported program](README.md#supported-program),
[runtime memory model](runtime.md#chain-memory-allocation)). The compiler's
current early-pass optimization instead executes `ASTValidationPass` and
`SymTabBuildPass` in a **native host shared library** before materializing their
tree and symbol graph back to the host
([native scope](../../jac/jaclang/compiler/native_scope.jac#L8),
[execution](../../jac/jaclang/compiler/jc_unit.jac#L168),
[compiler notes](../../jac/jaclang/compiler/README.md#native-early-analysis)).
The pass driver and product pipeline still schedule ordinary Jac pass walkers
on the host ([pass driver](../../jac/jaclang/compiler/driver/pass_driver.jac#L125),
[product pipeline](../../jac/jaclang/compiler/driver/pipeline.jac#L97)).

## Smallest useful experiment

Try a **numeric, local subset of `ASTValidationPass`** first. Its handlers
independently flag empty `MatchStmt` and `SwitchStmt` case lists and empty
`Enum` bodies, and reject some invalid assignment targets
([handlers](../../jac/jaclang/compiler/passes/impl/ast_validation_pass.impl.jac#L1)).
The whole pass is more complex: it tracks enter/exit context, walks ancestors,
inspects child lists, and emits source diagnostics
([pass declaration](../../jac/jaclang/compiler/passes/ast_validation_pass.jac#L94),
[context](../../jac/jaclang/compiler/passes/context.jac#L52)).

A prototype can keep parsing and the rest of validation on the CPU:

1. Flatten a parsed module to dense node IDs, kind IDs, child/role offsets,
   relevant token IDs, and source-node IDs. Measure this packing cost. Do not
   compute the candidate rule outcomes during packing.
2. Run one device thread per node. For the selected rules, read the packed
   topology and emit a diagnostic bitmask and node ID. Use a deterministic
   output slot per node; avoid device-side shared diagnostic-list mutation.
3. Copy the flags back, reconstruct `Alert` objects on the host, apply the
   existing diagnostic policy, and retain the CPU path as a fallback.

This is a **new compiler-pass offload prototype**, not a use of
`GpuWalkerRuntime` on the AST. The current GPU walker contract allows one node
type with numeric/boolean leaves, one empty edge type, and a restricted entry
ability, while `UniNode` has many node classes, role edges, object references,
lists and dictionaries ([GPU subset](README.md#supported-program),
[UniNode fields](../../jac/jaclang/compiler/frontend/unitree.jac#L156)). A direct
`GpuWalkerRuntime(ASTValidationPass, ...)` is therefore outside its supported
program. An explicit flat representation and a new kernel are required.

## What would count as success?

- **Correctness:** For a fixed Jac corpus containing valid and deliberately
  invalid syntax/AST shapes, CPU and GPU-subset paths produce identical
  diagnostic codes, source locations, severities, suppression behavior and
  stable ordering. Other validation rules remain on the CPU.
- **Safety:** Invalid or oversized packed inputs fail without publishing partial
  diagnostics. The original AST and symbols are unchanged by device work.
- **Performance:** Compare the existing host pass with **packing + transfer +
  kernel + copyback + alert reconstruction** and compare complete uncached
  compilation time too. Include small ordinary files and larger/batched
  modules. Record source/compiler hashes, GPU identity, warmups, raw paired
  times and correctness status. Count a speedup only when end-to-end time falls;
  a fast kernel alone is insufficient.

The existing native early-pass measurement is a useful baseline: on one
Threadripper build, AST validation fell from 34.25 ms to 11.22 ms after native
host migration, while the full AOT build improved 3.0%
([measurement](../../jac/jaclang/compiler/README.md#native-early-analysis)).
These are historical CPU results, not GPU predictions. Device transfer and
launch overhead may dominate ordinary single-file compilation, so a GPU win
is uncertain. If the local subset fails to beat the host path end to end, a
larger independent pass or batched modules would need their own measured case.

**Confidence:** High that the current compiler pass path runs on the host and
that the present walker GPU API cannot consume the full compiler AST; medium
that a flattened local-rule subset can be implemented; low that it will improve
ordinary compile time without measurement.
