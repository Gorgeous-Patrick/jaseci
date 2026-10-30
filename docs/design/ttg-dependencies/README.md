# Cross-ability walker dependencies

Branch: `feat/ttg-dependency-graph`.

See [replaceable prefetch admission](admission-model.md) for the decision-model interface, measured features and initial cost policy.

The dependency graph connects a value computed in an A handler to a branch in a B
handler reached through `visit`. Its context is a particular visit site, rather
than a pair of node types.

```text
A.on_a: x = here.value * 2
        self.mode = x + 1       <- completed-assignment checkpoint
        if self.mode > 0:
            visit B
                  |
                  | queued dispatch + walker state
                  v
B.on_b: if self.mode > 10:
            visit C
        else:
            visit D
```

After `self.mode` is assigned, a scalar snapshot determines both the A guard and
the B guard. Values 13, 3 and -1 predict B/C, B/D and an empty path respectively.
The graph retains the A-field read, local definition, walker-field definition,
both guards and both typed visits.

## API

`jaclang.runtime.ttg_dependencies.analyze_walker_dependencies(WalkerType)` obtains
the compiled Jac source AST and returns a `WalkerDependencyGraph`.

- Events: entry, input, assignment, branch, visit, join, phi, exit and effect barrier.
- Edges: data, control (true/false), statement order, visit dispatch and walker-state transfer.
- A state-transfer edge carries the source visit's event ID as its context.
- Walker fields are keyed as `self.mode`; locals and node fields are qualified by
  ability, for example `on_a::x` and `on_b::here.enabled`.
- Conditional definitions are joined with phi nodes. Definitions overwritten in
  B are killed before B's subsequent reads.

`graph.predict_after(assignment_event_id, snapshot, isolated=True)` evaluates the
remaining supported control flow from a completed assignment. It returns predicted
visit types, branch outcomes and unresolved requirements. Primitive scalar snapshots
are copied; prediction interprets a restricted expression tree with short-circuit
boolean/comparison semantics. It executes no user functions or attribute getters.

The checkpoint API is explicit. Callers supply current values for the point's
live inputs, such as `{"self.mode": 13}`. It can also replay pure local computations
from an earlier checkpoint, for example `{"on_a::x": 12}`. The automatic checkpoint interface below captures walker fields at compiler-selected
points; replaying arbitrary local inputs still uses this explicit API.

## Dispatch contract

The first executable fragment uses isolated transitions: a visit selects one target
of the stated exact node type, no previously queued visits or node-side handlers
intervene, and execution follows the modeled walker entry handlers. The caller
explicitly establishes this contract with `isolated=True`. A type-filter expression
alone does not prove target cardinality or exact dynamic type.

A queued visit runs after its source handler's continuation. Prediction stops when
that continuation contains further computation or effects. It also stops at multiple
matching handlers, node-field dependencies absent from the snapshot, unknown calls,
loops, unsupported expressions and unresolved visit shapes. These appear as graph
barriers or runtime unresolved requirements. A path containing a barrier cannot be
reported complete.

`complete` describes a conditional path of typed visit sites under this contract;
actual destination IDs and existence come from graph traversal. Thus an unresolved
B-field dependency remains visible even if all walker fields are known in A.

## Implementation and validation

The analyzer uses the Jac ability/assignment/branch/visit AST, and reuses TTG's typed
hop extraction. Scalar expressions use their token text through a restricted
standard-library expression parser. Assignment definitions and branch merges are
computed per handler; dispatch edges transport unresolved walker-entry reads under
the particular source visit's reaching definitions.

The graph separates dependency analysis from SQL execution and probability/cost
modeling. The `ttg_dependency` policy consumes certified selected visits through
the existing SQL and cache pipeline. Automatic captures are also available for
validation.

Tests: `jac test jac/tests/runtimelib/test_ttg_dependencies.jac`.
Fixtures: `jac/tests/runtimelib/fixtures/ttg_dependency_walkers.jac`.

The regression cases cover both B branches, a skipped B visit, local computation,
a B-field dependency, writes after a queued visit, conditional definition merges,
an overwrite in B, loops, multiple handlers, missing snapshot inputs and primitive
snapshot enforcement.

## Queue-aware decision certificates

A target can have other nodes before it in the FIFO queue. Their entry handlers
may modify unrelated fields while the target's branch dependencies remain stable.

```text
pending: [A1, A2, B]
B.on_b depends on self.mode
A1/A2 write self.counter       -> B path can be decided now
A1/A2 may write self.mode      -> decision is blocked
```

`graph.decide_pending(queue, target_index, ability, snapshot, point=None,
current_type=None)` checks one target ability against a concrete queue prefix.
Each queue item is a `PendingTraceNode` containing the actual runtime node class
and an optional identity. At a scheduler boundary, the queue prefix is the entire
intervening work. For a checkpoint inside a handler, `point` and `current_type`
include the handler's remaining CFG, later matching walker entry handlers and
matching node entry callbacks.

The certificate has three independent results:

| Field | Meaning |
| --- | --- |
| `stable` | The relevant entry dependencies have no potential intervening writes or unknown effects |
| `path_determined` | Stable dependencies and available scalar values determine the target handler's branch/visit trace |
| `execution_preserved` | The analyzed prefix has no unresolved effects or possible traversal cancellation |

The execution field concerns scheduling preservation under normally completing
handlers. It does not predict successful termination of arbitrary program code.
A disengage site can leave `stable` and `path_determined` true while making
`execution_preserved` false. The resulting path is conditional on target execution.

Required inputs come from backward slicing branch/visit dependencies through local
assignments, control edges and phi merges. An overwrite inside B kills the old
incoming dependency. May-write summaries cover both sides of intervening branches;
an unknown call, loop, aliased write or queue insertion remains a barrier.
Standard primitive walker fields use disjoint field names; custom setters and
properties remain unknown effects.

Runtime callback descriptors supply actual trigger classes and handler order,
including subtype matching. Unanalyzed inherited handlers and node-side entry
callbacks are barriers. Earlier handlers on the target node are included before
the selected target ability. The target trace describes that ability's statements;
visit sites enqueue work rather than recursively executing their destination handlers.

### FIFO scheduling details

Default visits append at the queue tail. If B is already queued, nodes appended by
A1/A2 go after B. Thus their handlers cannot affect B's entry state. Explicit visit
insertion is treated as unknown. The current OSP kernel drains the shared queue
before running pending node exits, so A1/A2 exit handlers execute after B entry;
their writes are excluded from the prefix certificate.

### Live checkpoints

`pending_trace_queue()` snapshots the active OSP queue after its consumed prefix,
filtering ignored anchors and recording actual node classes and identities.
`decide_live_pending(graph, point, target_index, ability)` obtains primitive walker
field values directly from the active walker, verifies its class against the graph,
and includes the current node/handler continuation. It accepts a completed-assignment or completed-visit checkpoint. The compiler
selects the supported sites automatically as described below.
The target index is relative to that snapshot, including repeated occurrences of a
node. A certificate applies to this snapshot and checkpoint.

Additional regressions:
`jac/tests/runtimelib/test_ttg_queue_dependencies.jac` and
`jac/tests/runtimelib/test_ttg_queue_execution.jac`. The execution test drives the
real OSP scheduling kernel with an in-memory backend and manually lowered fixture
callbacks, capturing a live checkpoint before unrelated A entries and deferred exits.

## Automatic compiler checkpoints

The Python backend analyzes each walker before emitting its first eligible
statement, including abilities linked to separate implementation files. It emits
an observational hook after:

- An ordinary assignment to a walker field needed by a branch or visit trace.
- A supported typed visit, after its targets have been appended to the real queue.

The compiler embeds a versioned serialized dependency graph, candidate target
abilities and point IDs in generated code. A site is identified by ability,
statement kind, line and column. Runtime capture reconstructs this graph once
per walker class and serialized plan, without reading or parsing source files.
Assignments to locals or irrelevant fields do not add hooks. This conservative
selection provides candidate checkpoints; it does not solve global earliest-point
placement or replay future assignments into hypothetical queue states.

An assignment hook can certify an already-queued B across unrelated A entries.
If B has not been enqueued yet, the hook records an empty queue; the visit hook
then examines actual selected targets. If the source continuation or an earlier
queued ability may overwrite a dependency, the certificate is blocked. A later
relevant assignment retries using the new value and remaining continuation.
A skipped branch produces no visit hook and no fabricated target.

Enable observation around a real traversal:

```jac
import from jaclang.runtime.ttg_checkpoints { capture_dependency_checkpoints }

with capture_dependency_checkpoints() as capture {
    origin spawn MyWalker();
}
# capture.hits: reached source sites and queue types
# capture.records: per-target queue certificate and predicted typed visits
```

Observation uses a ContextVar and nested captures restore the enclosing capture.
Outside a capture, emitted calls return without analyzing the queue or decoding
a dependency plan. The hook carries its lexical defining class through the
Python class cell. Inherited base-class bodies skip observation on a derived
walker, so an override cannot silently reuse a base-class plan. Records retain walker references and should be scoped to the
validation session. Certificates apply to their captured queue/checkpoint, rather
than forming a persistent cache of future execution.

Tests in `jac/tests/runtimelib/test_ttg_checkpoints.jac` execute compiled Jac
ability bodies through production server dispatch descriptors and the OSP kernel.
The fixtures use transient graphs; only the completion persistence callback is
omitted. Tests compare predicted branches with actual node entry order, exercise
post-visit overwrites, queue-prefix dependencies, cancellation, missing target
fields, nested capture, multiple source sites on one line, separate implementation
files and conservative inherited-body handling.

## Checkpoint-driven selective prefetch

Enable the runtime policy in `jac.toml`:

```toml
[run]
prefetching = "ttg_dependency"
prefetch_limit = 200
async_prefetch = "thread"
prefetch_workers = 1
```

Ordinary `spawn` activates a per-walk dependency-prefetch scope. Compiler hooks
produce certificates and the policy accepts those with `stable`,
`path_determined` and `execution_preserved` all true. Plan version 2 retains
visit edge type, target type, direction and origin. Supported plans use
single-hop typed visits from the queued target (`here`) or the active user root.
Field-filtered visits and unknown effects remain conservative barriers.

For each selected visit, the existing `compile_layered` template resolves one
layer from the actual origin ID. SQL retains edge/node subtype constraints and
direction, including undirected edges. The resolver excludes resident, raw-cached
and already-submitted IDs before applying the remaining prefetch budget. The
policy deduplicates identical origin/hop queries within a walk, including
certificates produced by repeated hooks.

`dispatch_prefetch(..., append=True)` merges outstanding IDs and threads into
the current wait group. Each new completion event covers all batches still
tracked by the session. The scope drains its background workers on exit. Payload
loading and raw-cache promotion use the existing Session implementation.

Speculative ID lookup uses `PgStore.rows_in_savepoint` inside the active
transaction. Local SQL errors roll back to that savepoint while preserving prior
foreground writes. This API uses the connection directly under the Store lock,
because the ordinary Store error path rolls back the full transaction.
Resolution errors are recorded and foreground traversal proceeds through its
normal demand path. Worker failures leave the same demand fallback available.

For direct integration tests, `dependency_prefetch(ctx, max_length=200,
mode="thread", workers=1)` exposes a run object. Configured spawns publish their
final summary at `ctx._ttg_dependency_metrics`:

- `submitted_ids`: unique IDs requested for background loading.
- `promoted_ids`: requested IDs actually promoted from raw cache by the foreground
  thread during this scope.
- `unused_cached_ids`: requested rows remaining in raw cache after draining.
- `unavailable_ids`: requests with neither recorded promotion nor a remaining raw
  row; driver traces distinguish worker failure, late fallback and invalidation.
- `plans`: origin, selected hops, resolved IDs, status and ID-resolution wall time.
- `errors`: planning/resolution/dispatch errors observed by the foreground hook.

ID-resolution wall time includes SQL construction, locking and execution. DB-call
profiling should separately record the driver boundary and count savepoint
commands, selected-path lookup, payload loading, reader cleanup and subsequent
demand lookup. Branch probabilities and cost-based admission are separate work.

`test_ttg_dependency_prefetch.jac` uses persisted graphs, fresh contexts and real
PostgreSQL. It covers both branches, reverse edges, node/edge subtypes, decoy-edge
rejection, repeated-hook deduplication, consumed raw rows, budget fallback,
cancellation, configured activation, local SQL recovery and failed workers.
