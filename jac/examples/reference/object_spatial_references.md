Object spatial references enable complex edge creation patterns in Jac's graph system, including bidirectional edges and typed edges with attributes.

**Basic Edge Creation**

Line 20 demonstrates the basic edge operator `++>` which creates a directed edge from one node to another. This operator connects `end` (the current node) to a newly created `node_a`, then assigns the new node back to `end` using the walrus operator pattern. This creates a chain of nodes connected by simple edges.

**Typed Edge with Forward Direction**

Line 22 shows creating a typed edge using the syntax `+>:connector:value=i:+>`. This creates an edge of type `connector` from the current `end` node to a new node. The `connector` edge type is defined on lines 13-15 with a `value` attribute that defaults to 10. The `:value=i:` portion sets the edge's `value` attribute to the current value of `i` during creation.

The pattern breaks down as:
- `+>` - Start of forward edge creation
- `:connector:` - Edge type specification
- `value=i:` - Attribute assignment for the edge
- `+>` - Completion of edge creation operator

**Typed Edge with Backward Direction**

Line 23 demonstrates creating a bidirectional or backward edge using `<+:connector:value=i:<+`. This creates a typed `connector` edge from the newly created node back to the `root` node (creating an incoming edge to root).

The pattern breaks down as:
- `<+` - Start of backward edge creation
- `:connector:` - Edge type specification
- `value=i:` - Attribute assignment for the edge
- `<+` - Completion of backward edge creation operator

**Edge Direction Summary**

| Operator Pattern | Direction | Description |
|------------------|-----------|-------------|
| `++>` | Forward | Simple directed edge |
| `+>:type:attr=val:+>` | Forward | Typed edge with attributes |
| `<+:type:attr=val:<+` | Backward | Incoming typed edge with attributes |

**Edge Type Definition**

Lines 13-15 define the edge type using `edge connector { has value: int = 10; }`. Edge types can have attributes just like node types. These attributes can be set during edge creation using the `:attr=val:` syntax within the edge operator.

**Graph Construction**

Lines 17-25 implement the `create` ability which constructs a complex graph structure. It creates a chain of three nodes (lines 19-21), then adds a node with a typed forward edge (line 22), and finally creates a node with a backward edge to root (line 23). The `visit [-->]` on line 24 continues the walker's traversal.

**Practical Usage**

This syntax is particularly useful for creating graphs where edges carry semantic meaning and data. For example, in a social network, you might use typed edges to represent different relationship types (friend, colleague, family) with attributes like "since" date or "strength" of connection.
