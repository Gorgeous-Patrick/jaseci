Object spatial spawn expressions provide an alternative syntax for spawning walkers on nodes, with the walker instance specified before the spawn keyword.

**Standard Spawn Syntax**

Line 27 demonstrates the alternative spawn syntax: `Adder() spawn root`. This creates an instance of the `Adder` walker and spawns it on the `root` node. The walker instance comes before the `spawn` keyword, followed by the target node.

This syntax differs from the more common form seen in other examples (`root spawn Walker()`), where the node comes first. Both forms are equivalent in functionality, but the `Walker() spawn node` form can be more readable when the walker construction is complex or when you want to emphasize the walker being created.

**Walker Setup**

Lines 3-5 define the `Adder` walker with an entry ability `do` that triggers when visiting the root node. The backtick syntax `\`root` specifies that this ability should execute when the walker enters a root node.

**Node Definition**

Lines 7-12 define a node type `node_a` with two integer attributes `x` and `y` (both defaulting to 0) and an ability `add` that executes when an `Adder` walker visits.

**Walker Implementation**

Lines 14-17 implement the walker's `do` ability. Line 15 uses `here ++> node_a()` to create a new `node_a` and connect it to the current node (which is `here`, the root in this case). Line 16 then uses `visit [-->]` to traverse to all outgoing edges, which will visit the newly created node.

**Node Ability Implementation**

Lines 19-23 implement the node's `add` ability. When the walker visits the node, this ability executes. Lines 20-21 set the node's attributes, and line 22 prints their sum. Note that line 22 explicitly converts the attributes to `int` before adding them, even though they're already typed as `int` - this may be defensive programming or a requirement of the implementation.

**Spawn Expression Semantics**

The spawn expression creates a walker instance and begins its execution on the specified node. The execution follows these steps:
1. Walker instance is created with any constructor arguments: `Adder()`
2. Walker is spawned on the target node: `spawn root`
3. The appropriate entry ability is triggered based on the node type (`\`root entry` in this case)
4. The walker executes its logic, potentially visiting other nodes

**Syntax Comparison**

Both spawn syntaxes are valid:
- `Walker() spawn node` - Walker-first syntax (used in this example)
- `node spawn Walker()` - Node-first syntax (used in other examples)

Choose the syntax that makes your code most readable for the specific context.
