# **Jac Library Mode: Pure Python with Jac's Power**

## **Introduction**

Every Jac program can be expressed as pure Python code using Jac's library mode. This means you get **100% of Jac's data-spatial programming capabilities** in regular Python syntax—no new language to learn, just powerful libraries to import.

Library mode is perfect for:
- **Python-first teams** wanting to adopt Jac gradually
- **Existing Python codebases** that need graph-based features
- **Understanding Jac's internals** by seeing the Python equivalent
- **Maximum interoperability** with Python tools and frameworks

### **Turn any Jac code example you see to Pure Python**

When you run `jac jac2lib myfile.jac`, Jac generates clean Python code that:
1. Imports from `jaclang.lib` instead of using aliased imports
2. Uses direct function calls like `spawn()` and `visit()` instead of `_jl.spawn()`
3. Produces readable, maintainable code suitable for library distribution

---

## **The Friends Network Example**

Let's walk through a complete example that demonstrates Jac's data-spatial programming in library mode.

### **The Jac Code**

Here's a social network graph with people connected by friendship and family relationships:

```jac
node Person {
    has name: str;

    can announce with FriendFinder entry {
        print(f"{visitor} is checking me out");
    }
}

edge Friend {}
edge Family {
    can announce with FriendFinder entry {
        print(f"{visitor} is traveling to family member");
    }
}

with entry {
    # Build the graph
    p1 = Person(name="John");
    p2 = Person(name="Susan");
    p3 = Person(name="Mike");
    p4 = Person(name="Alice");
    root ++> p1;
    p1 +>: Friend :+> p2;
    p2 +>: Family :+> [p1, p3];
    p2 +>: Friend :+> p3;
}

walker FriendFinder {
    has started: bool = False;

    can report_friend with Person entry {
        if self.started {
            print(f"{here.name} is a friend of friend, or family");
        } else {
            self.started = True;
            visit [-->];
        }
        visit [edge ->:Family :->];
    }

    can move_to_person with `root entry {
        visit [-->];
    }
}

with entry {
    result = FriendFinder() spawn root;
    print(result);
}
```

### **The Library Mode Python Equivalent**

Run `jac jac2lib friends.jac` to generate:

```python
from __future__ import annotations
from jaclang.lib import (
    Edge,
    Node,
    Path,
    Root,
    Walker,
    build_edge,
    connect,
    on_entry,
    refs,
    root,
    spawn,
    visit,
)


class Person(Node):
    name: str

    @on_entry
    def announce(self, visitor: FriendFinder) -> None:
        print(f"{visitor} is checking me out")


class Friend(Edge):
    pass


class Family(Edge):

    @on_entry
    def announce(self, visitor: FriendFinder) -> None:
        print(f"{visitor} is traveling to family member")


# Build the graph
p1 = Person(name="John")
p2 = Person(name="Susan")
p3 = Person(name="Mike")
p4 = Person(name="Alice")
connect(left=root(), right=p1)
connect(left=p1, right=p2, edge=Friend)
connect(left=p2, right=[p1, p3], edge=Family)
connect(left=p2, right=p3, edge=Friend)


class FriendFinder(Walker):
    started: bool = False

    @on_entry
    def report_friend(self, here: Person) -> None:
        if self.started:
            print(f"{here.name} is a friend of friend, or family")
        else:
            self.started = True
            visit(self, refs(Path(here).edge_out().visit()))
        visit(
            self,
            refs(
                Path(here).edge_out(edge=lambda i: isinstance(i, Family)).edge().visit()
            ),
        )

    @on_entry
    def move_to_person(self, here: Root) -> None:
        visit(self, refs(Path(here).edge_out().visit()))


result = spawn(FriendFinder(), root())
print(result)
```

---

## **Key Concepts Explained**

### **1. Nodes and Edges**

**In Jac:**
```jac
node Person {
    has name: str;
}

edge Friend {}
```

**In Library Mode:**
```python
from jaclang.lib import Node, Edge


class Person(Node):
    name: str


class Friend(Edge):
    pass
```

- Inherit from `Node` for graph nodes
- Inherit from `Edge` for relationships between nodes
- Use Python's class attributes for data fields

### **2. Walkers**

**In Jac:**
```jac
walker FriendFinder {
    has started: bool = False;
}
```

**In Library Mode:**
```python
from jaclang.lib import Walker


class FriendFinder(Walker):
    started: bool = False
```

- Inherit from `Walker` for graph traversal agents
- Walkers move through the graph and execute logic at each node

### **3. Abilities (Event Handlers)**

**In Jac:**
```jac
can report_friend with Person entry {
    print(f"{here.name} is a friend");
}
```

**In Library Mode:**
```python
from jaclang.lib import on_entry


@on_entry
def report_friend(self, here: Person) -> None:
    print(f"{here.name} is a friend")
```

- Use `@on_entry` decorator for entry abilities
- Use `@on_exit` decorator for exit abilities
- The `here` parameter represents the current node
- The `visitor` parameter (in node/edge abilities) represents the walker

### **4. Connecting Nodes**

**In Jac:**
```jac
root ++> p1;                      # Connect root to p1
p1 +>: Friend :+> p2;             # Connect p1 to p2 with Friend edge
p2 +>: Family :+> [p1, p3];       # Connect p2 to multiple nodes
```

**In Library Mode:**
```python
from jaclang.lib import connect, root

connect(left=root(), right=p1)
connect(left=p1, right=p2, edge=Friend)
connect(left=p2, right=[p1, p3], edge=Family)
```

- `connect()` creates directed edges between nodes
- `edge` parameter specifies the edge type
- Can connect to single nodes or lists of nodes

### **5. Spawning Walkers**

**In Jac:**
```jac
result = FriendFinder() spawn root;
```

**In Library Mode:**
```python
from jaclang.lib import spawn, root

result = spawn(FriendFinder(), root())
```

- `spawn()` starts a walker at a specific node
- `root()` returns the root node of the graph
- Returns the walker after traversal completes

### **6. Visiting Nodes**

**In Jac:**
```jac
visit [-->];                      # Visit all outgoing edges
visit [edge ->:Family :->];       # Visit only Family edges
```

**In Library Mode:**
```python
from jaclang.lib import visit, refs, Path

visit(self, refs(Path(here).edge_out().visit()))
visit(
    self, refs(Path(here).edge_out(edge=lambda i: isinstance(i, Family)).edge().visit())
)
```

- `Path()` creates a traversal path from a node
- `edge_out()` specifies outgoing edges
- `edge()` filters to edges only (not nodes)
- `visit()` marks the path for walker to follow
- `refs()` converts path to node references

---

## **Common Patterns**

### **Pattern 1: Simple Graph Traversal**

```python
from jaclang.lib import Node, Walker, spawn, visit, refs, Path, root, connect, on_entry


class Item(Node):
    value: int = 0


class Traverser(Walker):
    @on_entry
    def process(self, here: Item) -> None:
        print(f"Processing item: {here.value}")
        visit(self, refs(Path(here).edge_out().visit()))


# Build graph
items = [Item(value=i) for i in range(5)]
for i in range(len(items) - 1):
    connect(left=items[i], right=items[i + 1])
connect(left=root(), right=items[0])

# Traverse
spawn(Traverser(), root())
```

### **Pattern 2: Filtered Edge Traversal**

```python
from jaclang.lib import Node, Edge, Walker, spawn, visit, refs, Path, on_entry


class Person(Node):
    name: str


class Friend(Edge):
    pass


class Colleague(Edge):
    pass


class FriendFinder(Walker):
    @on_entry
    def find_friends(self, here: Person) -> None:
        # Only traverse Friend edges
        visit(
            self,
            refs(Path(here).edge_out(edge=lambda e: isinstance(e, Friend)).visit()),
        )
```

### **Pattern 3: Bidirectional Traversal**

```python
from jaclang.lib import Path, visit, refs

# Visit incoming edges
visit(self, refs(Path(here).edge_in().visit()))

# Visit both incoming and outgoing
visit(self, refs(Path(here).edge_any().visit()))
```

### **Pattern 4: Node Type Filtering**

```python
# Visit only Person nodes
visit(self, refs(Path(here).edge_out(node=lambda n: isinstance(n, Person)).visit()))

# Visit only edges, not nodes
visit(self, refs(Path(here).edge_out().edge().visit()))
```

---

## **Advanced Features**

### **Semantic Strings (AI Integration)**

```python
from jaclang.lib import sem


@sem(
    "Returns the weather for a given city.",
    {"city": "Name of the city to get weather for"},
)
class Weather(Node):
    city: str
    temp: float
```

### **Data Persistence**

```python
from jaclang.lib import save, jid

# Save a node to database
person = Person(name="Alice")
save(person)

# Get unique ID
node_id = jid(person)
```

### **Access Control**

```python
from jaclang.lib import perm_grant, perm_revoke

# Grant access
perm_grant(node, user, "read")

# Revoke access
perm_revoke(node, user, "write")
```

---

## **Complete Library Interface Reference**

### **Base Classes**

| Class | Description | Usage |
|-------|-------------|-------|
| `Obj` | Base class for all archetypes | Generic archetype |
| `Node` | Graph node archetype | `class MyNode(Node):` |
| `Edge` | Graph edge archetype | `class MyEdge(Edge):` |
| `Walker` | Graph traversal agent | `class MyWalker(Walker):` |
| `Root` | Root node type | Entry point for graphs |
| `Path` | Data-spatial path builder | `Path(node).edge_out()` |

### **Decorators**

| Decorator | Description | Usage |
|-----------|-------------|-------|
| `@on_entry` | Entry ability decorator | Executes when walker enters node/edge |
| `@on_exit` | Exit ability decorator | Executes when walker exits node/edge |
| `@sem(doc, fields)` | Semantic string decorator | AI/LLM integration metadata |

### **Graph Construction**

| Function | Description | Parameters |
|----------|-------------|------------|
| `connect(left, right, edge)` | Connect nodes with edge | `left`: source node(s)<br>`right`: target node(s)<br>`edge`: edge class (optional) |
| `disconnect(left, right)` | Remove edge between nodes | `left`: source node<br>`right`: target node |
| `build_edge(...)` | Create edge with properties | Various edge properties |
| `spawn_node(node_type, **kwargs)` | Create and spawn node | Node class and attributes |

### **Graph Traversal**

| Function | Description | Parameters |
|----------|-------------|------------|
| `spawn(walker, node)` | Start walker at node | `walker`: Walker instance<br>`node`: Starting node |
| `visit(walker, nodes)` | Visit specified nodes | `walker`: Walker instance<br>`nodes`: Node references |
| `disengage(walker)` | Stop walker traversal | `walker`: Walker to stop |
| `refs(path)` | Convert path to references | `path`: DataSpatialPath |
| `arefs(path)` | Async path references | `path`: DataSpatialPath |

### **Path Building**

| Method | Description | Returns |
|--------|-------------|---------|
| `Path(node)` | Create path from node | DataSpatialPath |
| `.edge_out(edge, node)` | Filter outgoing edges | Self (chainable) |
| `.edge_in(edge, node)` | Filter incoming edges | Self (chainable) |
| `.edge_any(edge, node)` | Filter any direction | Self (chainable) |
| `.edge()` | Edges only (no nodes) | Self (chainable) |
| `.visit()` | Mark for visit traversal | Self (chainable) |

### **Data Access**

| Function | Description | Returns |
|----------|-------------|---------|
| `root()` | Get root node | Root node instance |
| `get_object(id)` | Get node by ID | Node instance |
| `jid(node)` | Get node unique ID | String |
| `save(node)` | Persist node to database | None |
| `get_edges(node, dir, edge_type)` | Get edges from node | List of edges |
| `list_nodes()` | List all nodes | List of nodes |
| `list_walkers()` | List all walkers | List of walkers |
| `list_edges()` | List all edges | List of edges |

### **Permissions & Security**

| Function | Description | Parameters |
|----------|-------------|------------|
| `perm_grant(node, user, level)` | Grant permission | `node`: Target<br>`user`: User<br>`level`: Permission level |
| `perm_revoke(node, user, level)` | Revoke permission | Same as grant |
| `check_read_access(node)` | Check read permission | `node`: Target node |
| `check_write_access(node)` | Check write permission | `node`: Target node |
| `allow_root(root)` | Allow root access | `root`: Root to allow |
| `disallow_root(root)` | Disallow root access | `root`: Root to disallow |

### **Module & Import**

| Function | Description | Parameters |
|----------|-------------|------------|
| `jac_import(target, base_path)` | Import Jac module | `target`: Module name<br>`base_path`: Search path |
| `load_module(path)` | Load compiled module | `path`: Module path |
| `attach_program(program)` | Attach program to runtime | `program`: JacProgram |
| `list_modules()` | List loaded modules | Returns list |

### **Testing & Debugging**

| Function | Description | Parameters |
|----------|-------------|------------|
| `jac_test(func)` | Test function decorator | Marks function as test |
| `run_test(...)` | Run test suite | Various test parameters |
| `report(value)` | Report value from walker | `value`: Value to report |
| `printgraph(node, ...)` | Generate DOT graph | Node and visualization params |

### **Advanced Runtime**

| Function | Description | Use Case |
|----------|-------------|----------|
| `by(model)` | LLM decorator | AI function integration |
| `call_llm(model, mtir)` | Direct LLM call | Advanced LLM usage |
| `get_mtir(caller, args)` | Get method IR | LLM internals |
| `field(...)` | Define field metadata | Advanced field config |
| `impl_patch_filename(...)` | Patch implementation | Runtime modification |
| `create_archetype_from_source(...)` | Dynamic archetype creation | Runtime code generation |

---

## **Best Practices**

### **1. Type Hints**

Always use type hints for better IDE support:

```python
from typing import Optional


class Person(Node):
    name: str
    age: Optional[int] = None
```

### **2. Walker State**

Keep walker state minimal and immutable when possible:

```python
class Counter(Walker):
    count: int = 0  # Simple state

    @on_entry
    def increment(self, here: Node) -> None:
        self.count += 1
```

### **3. Path Filtering**

Use lambda functions for flexible filtering:

```python
# Filter by edge type
visit(
    self,
    refs(Path(here).edge_out(edge=lambda e: isinstance(e, (Friend, Family))).visit()),
)

# Filter by node attribute
visit(
    self,
    refs(Path(here).edge_out(node=lambda n: hasattr(n, "active") and n.active).visit()),
)
```

### **4. Clean Imports**

Import only what you need:

```python
# Good
from jaclang.lib import Node, Walker, spawn, visit, on_entry

# Avoid
from jaclang.lib import *
```

---

## **Migration Guide**

### **From Jac to Library Mode**

| Jac Syntax | Library Mode Python |
|------------|---------------------|
| `node Person { has name: str; }` | `class Person(Node):`<br>&nbsp;&nbsp;&nbsp;&nbsp;`name: str` |
| `edge Friend {}` | `class Friend(Edge):`<br>&nbsp;&nbsp;&nbsp;&nbsp;`pass` |
| `walker W { has x: int; }` | `class W(Walker):`<br>&nbsp;&nbsp;&nbsp;&nbsp;`x: int` |
| `root ++> node` | `connect(root(), node)` |
| `a +>: Edge :+> b` | `connect(a, b, Edge)` |
| `W() spawn root` | `spawn(W(), root())` |
| `visit [-->]` | `visit(self, refs(Path(here).edge_out().visit()))` |
| `visit [<--]` | `visit(self, refs(Path(here).edge_in().visit()))` |
| `visit [--]` | `visit(self, refs(Path(here).edge_any().visit()))` |
| `can f with T entry {}` | `@on_entry`<br>`def f(self, here: T): ...` |
| `disengage;` | `disengage(self)` |

---

## **Summary**

Library mode demonstrates that **Jac is Python**—just with powerful abstractions for data-spatial programming. You get:

✅ **100% Feature Parity**: Everything Jac can do, library mode can do
✅ **Clean Python**: No magic, just classes, decorators, and functions
✅ **Full IDE Support**: Type hints, autocomplete, and debugging work perfectly
✅ **Easy Integration**: Drop into any Python project without friction
✅ **Readable Output**: Generated code is maintainable and understandable

Whether you write `.jac` files or use library mode directly, you're writing Python with superpowers for graph-based, AI-native applications.
