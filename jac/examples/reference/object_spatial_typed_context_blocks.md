Object spatial typed context blocks demonstrate how walkers and nodes interact through ability implementations in Jac's spatial programming model.

**Walker Definition with Entry Ability**

Lines 3-5 define a walker `Producer` with an ability `produce` that is triggered when the walker encounters a root node. The backtick syntax `\`root entry` specifies that this is an entry ability for root nodes - meaning it executes automatically when the walker is spawned on or visits a root node.

**Node Definition with Entry Ability**

Lines 7-11 define a node type `Product` with a `number` attribute and an ability `make` that triggers when a `Producer` walker visits this node. The `with Producer entry` clause means this ability executes when a `Producer` walker enters a `Product` node.

**Walker Ability Implementation**

Lines 13-19 implement the walker's `produce` ability. This creates a chain of `Product` nodes:
- Line 14 initializes `end` to the current node (`here`, which is root initially)
- Lines 15-17 loop three times, each iteration creating a new `Product` node and connecting it to the previous node
- Line 16 uses the pattern `end ++> (end := Product(number=i + 1))` which connects `end` to a new node, then reassigns `end` to point to that new node
- Line 18 uses `visit [-->]` to traverse to all outgoing edges, visiting the created nodes

**Node Ability Implementation**

Lines 21-24 implement the node's `make` ability. When the `Producer` walker visits a `Product` node:
- Line 22 prints a message including `self` (the current node instance)
- Line 23 calls `visit [-->]` to continue traversal to any outgoing edges from this node

**Typed Context Semantics**

The "typed context" refers to the ability system where abilities are triggered based on the types involved:
- The walker type (`Producer`)
- The node type (`Product`)
- The interaction type (`entry` - when walker enters the node)

When `root spawn Producer()` executes on line 27:
1. The `Producer.produce` ability executes (matches `\`root entry`)
2. This creates three `Product` nodes in a chain
3. The walker visits these nodes via `visit [-->]`
4. Each `Product` node's `make` ability executes (matches `Producer entry`)
5. Each node continues the traversal with its own `visit [-->]`

**Ability Matching**

Abilities are matched based on:
- **Walker type**: Which walker is visiting
- **Node type**: Which type of node the ability belongs to
- **Trigger condition**: `entry`, `exit`, or specific event

This creates a powerful dispatch system where behavior is determined by the types of both the walker and the node, enabling polymorphic spatial programming.

**Execution Flow**

The execution flow for this example:
1. Walker spawns on root → `Producer.produce` executes
2. Creates chain: root → Product(1) → Product(2) → Product(3)
3. Walker visits Product(1) → `Product.make` executes, prints message
4. Walker visits Product(2) → `Product.make` executes, prints message
5. Walker visits Product(3) → `Product.make` executes, prints message
