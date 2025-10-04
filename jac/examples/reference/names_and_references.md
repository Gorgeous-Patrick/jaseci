Jac provides several special reference names that are automatically available in specific contexts, allowing you to access important objects and perform common operations.

**self - Instance Reference**

The `self` reference refers to the current instance of an object. It's used to access instance attributes and methods from within the object's methods. Lines 9-10 show `self` being used in the `init` method to set instance attributes. Line 26 demonstrates using `self` to access the instance's `species` and `sound` attributes. The `self` reference is automatically available in all instance methods.

**super - Parent Class Reference**

The `super` reference allows access to the parent class's methods, enabling proper method delegation in inheritance hierarchies. Lines 31 and 39 demonstrate calling the parent class's `init` method using `super.init(...)`. This ensures that parent class initialization logic executes before child class initialization. Without `super`, you cannot access overridden parent methods from a child class.

**init - Constructor Special Method**

The `init` method (lines 8, 30, 37) is automatically called when an object is instantiated. It serves as the constructor and is where you typically initialize instance attributes. When a class inherits from a parent, the child's `init` should call `super.init()` to ensure proper initialization of parent attributes.

**postinit - Post-Initialization Hook**

Lines 16-22 demonstrate the `postinit` method, which is called automatically after `init` completes. This is declared using the `by postinit` syntax on line 16. The `postinit` method is useful for initialization logic that depends on the object being fully constructed, or for setting default values for attributes. Line 20 sets `self.trick` and line 21 prints a message, both executing after the main initialization.

**here - Current Node Reference**

In spatial/graph contexts, `here` refers to the current node being visited. Line 48 shows using `here` to reference the current node in a walker's entry ability. Line 65 demonstrates accessing the current node's attributes with `here.name`. The `here` reference is automatically available in walker abilities and node abilities that are triggered by walker visits.

**visitor - Current Walker Reference**

The `visitor` reference (line 51) refers to the walker currently executing. It's available within node abilities that are triggered by walker visits, allowing nodes to access walker state or call walker methods. This enables bidirectional communication between walkers and nodes.

**root - Root Node Reference**

The `root` reference (line 54) refers to the root node of the graph. It's available in spatial contexts and provides a way to access the graph's entry point. Lines 82-83 note that `root` is available in spatial/graph contexts. While commented out in this example, line 86 shows typical usage: `root ++> loc1` creates an edge from the root node to another node.

**Special Reference Availability**

The table below summarizes where each special reference is available:

| Reference | Available In | Purpose |
|-----------|-------------|---------|
| `self` | Instance methods | Access current instance |
| `super` | Instance methods | Access parent class methods |
| `here` | Walker/node abilities | Current node in graph traversal |
| `visitor` | Node abilities | Current walker visiting the node |
| `root` | Spatial contexts | Root node of the graph |

**Keyword Escaping**

Lines 69-71 mention keyword escaping with `<>` syntax. This allows using reserved keywords as identifiers by wrapping them in angle brackets, such as `<>class` or `<>for`. However, this feature should be used sparingly as it can reduce code readability.
