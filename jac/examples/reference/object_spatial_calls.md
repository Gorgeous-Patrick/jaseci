Object spatial calls are special invocation operators that spawn and execute walkers on nodes in the graph with different traversal semantics.

**Walker and Node Setup**

Lines 3-16 define a walker `Creator` and a node type `node_1`. The walker has an entry ability `func2` (line 4) that triggers when visiting the root node. The node has an ability `func_1` (line 10) that executes when a `Creator` walker visits it. Line 13-16 implements `func_1` to print the current node and continue traversal using `visit [-->]`.

**Graph Construction**

Lines 18-24 implement the walker's `func2` ability, which constructs a linked chain of nodes. Line 19 captures the current node in `end`. Lines 20-22 create a loop that generates 5 nodes, each connected to the previous one using `++>` (the connect and assign pattern). Each iteration creates a new `node_1`, assigns it to `end`, and connects the previous `end` to the new node.

**Spatial Call Operator :> (Depth-First)**

Line 27 demonstrates the `:>` operator: `root spawn :> Creator`. This operator spawns a walker and executes it depth-first on the graph. The walker starts at the root node and follows edges in a depth-first manner, visiting child nodes completely before siblings. This means when the walker encounters the chain of nodes created in `func2`, it will traverse all the way to the end of the chain before backtracking.

**Spatial Call Operator |> (Breadth-First)**

Line 28 demonstrates the `|>` operator: `root spawn |> Creator`. This operator spawns a walker and executes it breadth-first on the graph. The walker visits nodes level-by-level, processing all nodes at the current depth before moving to the next depth level. For the chain of nodes, this means the walker visits each level of the graph structure in order of distance from the root.

**Traversal Semantics Comparison**

The two spatial call operators provide different graph traversal strategies:

| Operator | Traversal | Use Case |
|----------|-----------|----------|
| `:>` | Depth-first | Exploring paths to their end, recursive structures |
| `|>` | Breadth-first | Level-order processing, shortest paths |

**spawn Keyword**

The `spawn` keyword (lines 27-28) creates and launches a walker instance. When combined with spatial call operators, it determines how the walker traverses the graph. The syntax `node spawn operator Walker` spawns a walker at the specified node and begins traversal according to the operator's semantics.

**visit Statement**

Lines 15 and 23 use `visit [-->]`, which tells the walker to continue visiting all outgoing edges from the current node. The `[-->]` edge expression selects all edges going out from the current node, and `visit` triggers the walker to traverse to the nodes at the other end of those edges.
