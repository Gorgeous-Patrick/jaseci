Visit statements are a core feature of Jac's spatial programming model, controlling how walkers traverse graph structures by specifying which nodes to visit next. They embody the fundamental paradigm shift in Object-Spatial Programming from "data flows to computation" to "computation flows to data"—instead of data being passed to stationary functions, walkers (autonomous computational entities) move through the data space (nodes and edges), processing information contextually based on their current location.

**Basic Visit with Edge Expression**

Line 19 demonstrates the simplest visit statement: `visit [-->];`. This tells the walker to traverse all outgoing edges from the current node. The `[-->]` is an edge expression that selects all edges going out from the current node. When this executes, the walker will visit each node connected by these edges.

**Visit with Else Clause**

Lines 6-9 show a visit statement with an else clause: `visit [-->] else { ... }`. The else clause executes when there are no edges to visit (when the edge expression matches no edges).

In this example:
- If `[-->]` finds outgoing edges, the walker visits those nodes
- If `[-->]` finds no edges (dead end), the else block executes
- Lines 7-8 visit the root node and then disengage (stop the walker)

This pattern is useful for handling terminal nodes or implementing backtracking behavior.

**Visit with Direct Node Reference**

Lines 7 and 28 show visiting a specific node: `visit root;`. Instead of an edge expression, you can directly specify a node to visit. This is useful for:
- Jumping to specific nodes
- Returning to a known location (like root)
- Implementing custom traversal patterns

**Typed Visit Expression (Commented)**

Line 16 shows a commented-out typed visit: `visit :node: [-->];`. The `:node:` syntax would filter the traversal to only visit nodes of a specific type. This allows walkers to selectively visit nodes based on their type, though this example indicates it may not be currently active.

**Conditional Visit**

Lines 31-34 demonstrate conditional visiting based on walker state. The visit only occurs if `self.count < 5`:
```
if self.count < 5 {
    visit [-->];
    self.count += 1;
}
```

This pattern enables:
- Limiting traversal depth
- Conditional exploration based on walker state
- Implementing search algorithms with termination conditions

**Edge Expressions**

Edge expressions specify which edges to follow:

| Expression | Meaning |
|------------|---------|
| `[-->]` | All outgoing edges |
| `[<--]` | All incoming edges |
| `[<-->]` | All edges (both directions) |

These can be combined with type filters and conditions for sophisticated traversal control.

**Walker Definition and Abilities**

Lines 3-11 define a walker with an ability that uses visit statements. The `can travel with \`root entry` syntax means this ability executes when the walker enters a root node. The visit statements within control how the walker continues its traversal.

Lines 13-21 define another walker showing the straightforward visit without else clause.

Lines 23-36 define a walker with state (`count`) that uses conditional visiting to control traversal behavior.

**Node Abilities**

Lines 38-50 define nodes with abilities that execute when walkers visit them. Line 39 shows `can speak with Visitor entry`, meaning this ability triggers when a `Visitor` walker enters an `item` node. These abilities can contain their own logic but don't control the walker's traversal - that's handled by visit statements in the walker.

**Graph Setup**

Lines 54-56 build a graph structure by creating 5 `item` nodes connected to root. Line 59 spawns the `Visitor` walker, which will traverse this graph according to its visit statements.

**Visit Statement Semantics**

When a visit statement executes:
1. The edge expression is evaluated to find matching edges
2. For each matching edge, the walker queues a visit to the target node
3. Node entry abilities execute as nodes are visited
4. The walker continues until no more visits are queued or it disengages

**Traversal Control**

Visit statements work with other control statements:
- `disengage` (line 8): stops the walker immediately
- `if` conditions: control whether visits occur
- `else` clauses: handle cases where no edges match

**Multiple Visits**

A walker can have multiple visit statements in sequence, each potentially visiting different sets of nodes. The walker maintains a queue of pending visits and processes them according to the traversal strategy (depth-first or breadth-first, determined by the spawn operator).
