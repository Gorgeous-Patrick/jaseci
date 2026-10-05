# Named cursors on Python CPU walkers

A walker declares independent, untyped access channels before its abilities:

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
{"a": start_a, "b": start_b} spawn Dot();
```

Bindings have exactly the declared string keys. Each value is a node, a node
list, or `None` (an empty channel). Either operand order of `spawn` is accepted.
Channels do not declare node types. Each ability declares its own complete set
of channel/type entry predicates; subtype matching uses ordinary `isinstance`.

## Event and queue semantics

Each channel has its own FIFO queue. A round consumes one fresh arrival from
every channel. All positions remain stable until all matching abilities for that
round have run, in declaration order. Each matching ability runs once per
round. Every predicate must match; a mismatch does not execute that ability,
does not search ahead, and does not synthesize another entry for a held node.
Another matching ability may visit through a heterogeneous intermediate node.

`visit[a]` evaluates implicit edge origins at the current node of channel `a`,
then enqueues only that channel's targets. Explicit origins retain their meaning.
Visit filtering, destroyed targets, insertion indices and visit-else use the
existing visit implementation. Enqueuing does not change any current position.
Multiple successors are consumed in queue order, paired with the other queues;
there is no Cartesian product. Duplicate arrivals remain separate entries.

After a round, each channel advances to its next queued arrival. If an ability
does not visit a channel, that channel can still advance through already queued
siblings. Otherwise it becomes exhausted. Traversal ends as soon as any channel
is exhausted; unmatched tails are discarded. `None`/empty initial queues cause
zero rounds. Multiple abilities can enqueue in the same round. All start
bindings are validated before any ability executes.

This is an arrival-event barrier, not a repeated condition trigger on stable
nodes. A single old entry is never reused when another cursor advances. The
legacy single-channel spawn, here, visit, and walker/node entry/exit engine is
unchanged and remains the path for walkers without cursor declarations.

## First implementation boundaries

Named cursors support synchronous, local, non-inherited walker definitions,
joint entry abilities, private walker state, scalar/object node fields, loops,
conditionals, reports, nested spawning and disengage. Node-side event callbacks
on encountered nodes are rejected because their visitor/here and entry/exit
ordering has no declared multi-channel contract. Joint exit events, partial
channel signatures, ordinary event abilities mixed with joint abilities,
async abilities, unqualified here/visit, and out-of-line joint
implementations are rejected. Here selections are read-only; node fields may
be mutated. Cursor names are identifiers, not runtime variables; dynamic cursor
selection is unsupported. Implicit edge origins require a named visit; elsewhere
use an explicit `here[a]` origin.
Cursor selections and visits must appear directly in a joint entry ability body;
ordinary helpers can receive selected nodes as arguments. Exactly one cursor
declaration is allowed per walker.
Visits must target nodes; visiting edge objects is rejected. Start bindings on
destroyed nodes are rejected; destroyed nodes remaining in queues are skipped.
`skip` retains its ordinary ability-return behavior: already queued visits are
retained and later matching abilities in the same round still execute.

GPU, native CPU and JavaScript lowering and physical layout optimization are
outside this implementation. Named cursors must be compiled for Python CPU.

## Examples and verification

```bash
jac run jac/examples/cursors/dot.jac
jac run jac/examples/cursors/matmul.jac
PYTHONPATH=jac python scripts/test_named_cursors.py -v
jac test jac/tests/runtimelib/test_named_cursors.jac
```

The dot example uses two channels of the same `Scalar` type and prints 32.
The matrix example prints `[[58, 64], [139, 154]]`. Every input and output node
has exactly one int field. Each A row is a RowNext chain and each B column is a
ColumnNext chain. Walkers for different output cells share those input nodes;
only the output node's int is updated. Host lists build and retain graph handles,
not extra numeric buffers stored on nodes.
