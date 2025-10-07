**Walker Visit and Disengage (OSP)**

Walker visit and disengage statements are core control mechanisms in Jac's Object Spatial Programming (OSP) model. The `visit` statement directs walkers to traverse to nodes in the graph, while `disengage` immediately terminates the walker's execution. Together, they enable sophisticated graph traversal patterns for spatial computation.

**What are Walker Visit and Disengage Statements?**

In OSP, walkers are autonomous agents that traverse graph structures, executing code at each node they visit. The visit and disengage statements control this traversal:

- **`visit`**: Directs the walker to move to specific nodes based on edge patterns or expressions
- **`disengage`**: Immediately stops the walker, terminating all further traversal and code execution

These statements work together to implement graph algorithms, searches, data collection, and distributed computation patterns.

**Why Combine Visit and Disengage?**

Visit and disengage are complementary operations that form the foundation of walker control flow:

1. **`visit`** enables forward progress through the graph
2. **`disengage`** provides early termination and exit conditions
3. Together they implement complex traversal strategies (DFS, BFS, search, filtering)

Understanding both is essential for effective spatial programming in Jac.

---

## VISIT STATEMENTS

The `visit` statement moves a walker to new nodes in the graph, where it can execute abilities.

### Basic Visit Syntax

```
visit <expression>;
```

The expression can be:
- An edge filter pattern (e.g., `[-->]`)
- A specific node reference (e.g., `self.target`)
- A node collection or list

**Basic Visit to Outgoing Edges (lines 17-27)**

Lines 17-27 demonstrate the simplest visit pattern:

```jac
walker BasicVisitor {
    can start with `root entry {
        print("BasicVisitor: visiting outgoing edges");
        visit [-->];
    }
}
```

Line 21 uses `visit [-->]` to traverse to all nodes connected by outgoing edges. The walker's `visit_person` ability (line 24) then executes at each Person node.

**How Visit Works**:
1. Walker starts at root node
2. `visit [-->]` finds all outgoing edges
3. Walker clones and moves to each connected node
4. Node-specific abilities execute at each destination
5. Traversal continues from each new location

---

### Visit with Else Clause

The else clause handles the case when no nodes match the visit pattern.

**Syntax**:
```
visit <expression> else { <statements> }
```

**Visit with Else (lines 33-49)**

Lines 33-49 show how to handle empty edge sets:

```jac
walker VisitWithElse {
    can start with `root entry {
        visit [-->] else {
            print("VisitWithElse: no outgoing edges from root");
        }
    }
}
```

Line 36: `visit [-->] else { ... }` - if no outgoing edges exist, the else block executes instead.

Line 45-47: At leaf nodes (nodes with no outgoing edges), the else clause detects the end of a branch.

**Use Cases**:
- Detecting leaf nodes in a tree
- Handling empty graph sections
- Default behavior when no edges match filters

---

### Direct Node Visit

Visit a specific node directly, regardless of graph structure.

**Direct Visit (lines 55-67)**

Lines 55-67 demonstrate visiting a specific node:

```jac
walker DirectVisit {
    has target: Person;

    can start with `root entry {
        visit self.target;
    }
}
```

Line 61: `visit self.target` moves directly to the target node stored in the walker's field. This bypasses normal graph traversal - the walker teleports to the specific node.

**When to Use Direct Visit**:
- Jump to a known node without traversing edges
- Implement teleportation or fast-travel patterns
- Visit nodes based on walker state or computation results

---

### Typed Edge Visit

Filter visits to only specific edge types.

**Typed Visit (lines 73-84)**

Lines 73-84 show type-based edge filtering:

```jac
walker TypedVisit {
    can start with Person entry {
        visit [->:Friend:->];
    }
}
```

Line 76: `visit [->:Friend:->]` only traverses `Friend` edges, ignoring all other edge types.

**Edge Type Syntax**:
- `[->:EdgeType:->]` - edges of specific type
- `[-->]` - all outgoing edges (any type)
- `[<--]` - all incoming edges
- `[<->]` - all edges (bidirectional)

This enables selective traversal based on relationship types (friends, colleagues, dependencies, etc.).

---

### Filtered Visit with Edge Attributes

Visit edges based on attribute conditions.

**Filtered Visit (lines 90-101)**

Lines 90-101 demonstrate attribute-based filtering:

```jac
walker FilteredVisit {
    can start with Person entry {
        visit [->:Colleague:strength > 5:->];
    }
}
```

Line 94: `visit [->:Colleague:strength > 5:->]` only traverses `Colleague` edges where the `strength` attribute is greater than 5.

**Filter Syntax**:
```
[->:EdgeType:condition:->]
```

Where `condition` can be any boolean expression using edge attributes:
- `strength > 5`
- `weight <= 10`
- `active == True`
- `created_at > some_date`

**Use Cases**:
- Finding strong connections
- Weight-based graph algorithms
- Filtering by relationship properties

---

## DISENGAGE STATEMENTS

The `disengage` statement immediately terminates the walker's execution.

### Basic Disengage Syntax

```
disengage;
```

When executed, disengage:
1. Stops the current ability immediately
2. Prevents any code after the disengage from running
3. Terminates the walker completely - no further nodes are visited
4. Returns control (the walker is done)

**Basic Disengage (lines 107-126)**

Lines 107-126 show simple disengage usage:

```jac
walker BasicDisengage {
    can visit_person with Person entry {
        print(f"BasicDisengage: at {here.name}");
        if here.name == "Bob" {
            print("BasicDisengage: found Bob, disengaging");
            disengage;
        }
        print(f"BasicDisengage: continuing from {here.name}");
        visit [-->];
    }
}
```

Lines 118-120: When the walker finds Bob, it disengages. Line 122 never executes for Bob because disengage stops execution immediately.

**Key Point**: Line 123 (`visit [-->]`) also doesn't execute when disengaged, so no further traversal happens.

---

### Conditional Disengage

Disengage based on walker state or computation.

**Conditional Disengage (lines 132-153)**

Lines 132-153 implement count-based termination:

```jac
walker ConditionalDisengage {
    has max_visits: int = 2;
    has visit_count: int = 0;

    can count_visits with Person entry {
        self.visit_count += 1;
        if self.visit_count >= self.max_visits {
            disengage;
        }
        visit [-->];
    }
}
```

Line 145: Tracks how many nodes have been visited
Line 147-149: Disengages after reaching max visits
Line 150: Only executes if max not reached

This pattern implements early termination based on walker state.

---

### Search with Disengage

Use disengage to exit as soon as a target is found.

**Search Walker (lines 159-181)**

Lines 159-181 demonstrate search-and-terminate:

```jac
walker SearchWalker {
    has target_name: str;
    has found: bool = False;

    can check with Person entry {
        if here.name == self.target_name {
            self.found = True;
            disengage;
        }
        visit [-->];
    }
}
```

Lines 173-176: When target is found, set flag and disengage immediately
Line 177: Only continues searching if target not found yet

**Optimization**: Disengage prevents wasted traversal after finding the target. Without it, the walker would visit every node in the graph.

---

### Immediate Code Termination

Disengage stops code execution at the exact line it's called.

**Immediate Stop (lines 203-212)**

Lines 203-212 demonstrate execution stopping:

```jac
walker ImmediateStop {
    can self_destruct with `root entry {
        print("ImmediateStop: before disengage");
        disengage;
        print("ImmediateStop: after disengage (never printed)");
    }
}
```

Line 207: This prints
Line 208: Disengage executes here
Line 209: **Never executes** - code after disengage is unreachable

This is similar to `return` in functions, but for walkers.

---

## COMBINED VISIT AND DISENGAGE PATTERNS

Real-world walker logic combines both visit and disengage for complex traversal.

**Multiple Visit Strategies (lines 187-201)**

Lines 187-201 show a walker with multiple phases:

```jac
walker MultiVisit {
    has visit_phase: int = 1;

    can phase_one with Person entry {
        if self.visit_phase == 1 {
            self.visit_phase = 2;
            visit [-->];
        }
    }

    can phase_two with Person entry {
        if self.visit_phase == 2 {
            print(f"MultiVisit: phase 2 at {here.name}");
        }
    }
}
```

The walker changes strategy based on internal state, visiting different nodes in different ways.

**Complex Traversal (lines 218-247)**

Lines 218-247 combine multiple concepts:

```jac
walker ComplexTraversal {
    has depth: int = 0;
    has max_depth: int = 2;

    can traverse with Person entry {
        self.depth += 1;
        if self.depth >= self.max_depth {
            disengage;
        }
        visit [-->] else {
            print(f"leaf node at {here.name}");
        }
    }
}
```

This walker implements depth-limited traversal with:
- Depth tracking (line 228)
- Depth-based disengage (lines 231-233)
- Else clause for leaf detection (lines 235-237)

---

## VISIT VS DISENGAGE: KEY DIFFERENCES

| Feature | `visit` | `disengage` |
|---------|---------|-------------|
| **Purpose** | Move to new nodes | Stop walker completely |
| **Effect** | Continues traversal | Ends traversal |
| **Scope** | Creates new contexts at destinations | Terminates current context |
| **Code after** | Statement after visit may execute | Code after disengage never runs |
| **Use case** | Progress through graph | Exit conditions, early termination |

**Important**: Disengage is final - once called, the walker cannot visit more nodes.

---

## TRAVERSAL PATTERNS

### Breadth-First Search (BFS)
Use `visit [-->]` to visit all neighbors before going deeper. Walkers naturally implement BFS by visiting all edges at once.

### Depth-First Search (DFS)
Visit one edge at a time, storing others for later. Combine with walker state to track path.

### Search and Exit
Use `visit` to explore + `disengage` when found (lines 159-181).

### Bounded Traversal
Track depth/count and `disengage` at limit (lines 218-247).

### Filtered Traversal
Use typed edges or attribute filters to visit only relevant nodes (lines 73-101).

---

## EXECUTION MODEL

**Visit Execution**:
1. Evaluate the visit expression
2. Find all matching nodes/edges
3. For each match:
   - Clone walker state
   - Move walker to node
   - Execute node-specific ability
   - Continue from new location

**Disengage Execution**:
1. Stop current ability immediately
2. Discard walker instance
3. Return control to spawn point
4. Walker object remains accessible but inactive

**Graph Setup (lines 252-271)**

Lines 252-271 build the test graph:
- Creates 5 Person nodes (Alice, Bob, Charlie, Diana, Eve)
- Connects them with various edges
- Adds typed edges (Friend, Colleague) with attributes
- Demonstrates different edge structures for testing

**Walker Execution (lines 273-302)**

Lines 273-302 spawn walkers to demonstrate all patterns:
- Each print statement marks a new example
- Walkers execute independently
- Output shows traversal behavior
- Return values (like `w.found`) show walker state after completion

---

## WHEN TO USE VISIT AND DISENGAGE

**Use Visit When**:
- Traversing graph structures
- Implementing graph algorithms
- Distributed computation across nodes
- Collecting data from multiple locations
- Following relationships between entities

**Use Disengage When**:
- Search target is found
- Resource limits are reached (depth, count, time)
- Error conditions occur
- Computation is complete
- Early exit optimizations are needed

**Use Together When**:
- Implementing search algorithms
- Bounded or limited traversal
- Conditional exploration
- Resource-aware computation
- Complex multi-phase traversal

---

## BEST PRACTICES

1. **Always handle leaf nodes**: Use `else` clauses to detect when no edges exist
2. **Limit traversal**: Use disengage with depth/count limits to prevent infinite traversal
3. **Use typed edges**: Filter by edge type to traverse only relevant relationships
4. **Track walker state**: Store visited nodes, depth, results in walker fields
5. **Disengage early**: Exit as soon as goal is met to save computation
6. **Test edge cases**: Empty graphs, single nodes, cycles, disconnected components
7. **Document traversal logic**: Complex visit patterns benefit from comments

**Common Pitfall**: Forgetting to disengage in searches leads to traversing the entire graph even after finding the target.

**Performance Tip**: Use edge filters (`[->:Type:condition:->]`) to minimize unnecessary visits.

---

## COMPARISON WITH TRADITIONAL PROGRAMMING

**Visit vs For Loop**:
- Visit: Declarative spatial traversal
- For loop: Imperative iteration over collections

**Disengage vs Return**:
- Disengage: Terminates entire walker (all pending visits)
- Return: Exits current function only

**OSP Advantages**:
- Natural graph representation
- Automatic parallelization potential
- Declarative relationship traversal
- Built-in spatial semantics

The combination of visit and disengage makes OSP uniquely suited for graph-based computation, spatial data processing, and distributed algorithms.
