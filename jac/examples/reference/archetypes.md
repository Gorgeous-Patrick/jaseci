This example provides a comprehensive overview of Jac's core archetype system, which defines the fundamental building blocks for structuring programs. Jac's Object-Spatial Programming (OSP) model introduces four primary archetypes: obj, node, edge, and walker, each serving distinct purposes in the language's object-spatial programming paradigm. Additionally, Jac supports the traditional `class` keyword for backward compatibility with Python and traditional OOP patterns.

**Helper Function for Demonstration**

Lines 3-8 define a decorator function `print_base_classes` that prints the base classes of a type. This will be used later to demonstrate inheritance chains. The function takes a class type, prints its base classes using list comprehension to extract `__name__` attributes, and returns the class unchanged (as decorators should).

**Class Archetype**

Line 11 shows the simplest form: `class Animal {}`. Classes in Jac are similar to traditional object-oriented classes. They define types that can be instantiated and inherited from, serving as the foundation for object-oriented programming patterns.

**Object Archetype**

Line 14 introduces `obj Domesticated {}`. Object archetypes (`obj`) are one of the four core OSP archetypes. They provide backward compatibility with traditional OOP concepts while participating in Jac's spatial programming model. Objects can be used to create instances and participate in inheritance hierarchies.

**Node Archetype with Inheritance**

Lines 17-18 demonstrate a node archetype with multiple inheritance and a decorator. Nodes are spatial archetypes designed to represent vertices in Jac's spatial graph system. The syntax `node Pet(Animal, Domesticated)` shows that `Pet` inherits from both `Animal` and `Domesticated`, demonstrating multiple inheritance. The `@print_base_classes` decorator will print the base classes when this archetype is defined.

**Edge Archetypes**

Lines 21 and 24 show edge archetypes, which represent first-class relationships between nodes in the spatial graph. Unlike traditional OOP where relationships are implementation details (references or foreign keys), OSP elevates relationships to first-class status through edges. Edges can carry their own data, behavior, and computational logic. Line 21 shows a basic edge: `edge Relationship {}`. Line 24 demonstrates an edge with an access modifier: `edge :pub Connection {}`, where `:pub` marks the edge as public.

**Walker Archetypes with Inheritance**

Lines 27-32 demonstrate walker archetypes and inheritance chains. Walkers are autonomous computational entities that traverse the node-edge structure, embodying the fundamental paradigm shift in OSP from "data flows to computation" to "computation flows to data." Rather than data being passed to stationary functions, walkers move through the data space (nodes and edges), processing information contextually based on their current location:
- Line 27: `walker Person(Animal)` - Person inherits from Animal
- Line 29: `walker Feeder(Person)` - Feeder inherits from Person (and transitively from Animal)
- Lines 31-32: `walker Zoologist(Feeder)` - Creates a three-level inheritance chain: Zoologist → Feeder → Person → Animal

**Async Walker**

Line 35 shows `async walker MyWalker {}`, demonstrating that walkers can be marked as asynchronous to support concurrent operations and async/await patterns.

**Access Modifiers**

Lines 38-40 demonstrate Jac's access control system using tags:
- `:priv` - Private visibility (line 38)
- `:pub` - Public visibility (line 39)
- `:protect` - Protected visibility (line 40)

These access modifiers control the visibility and accessibility of archetypes across module boundaries.

**Forward Declarations and Implementation**

Lines 43-56 demonstrate the separation of archetype declaration and implementation using semicolon syntax and `impl` blocks:

Lines 43-44 show forward declarations using semicolons:
- `class ForwardDeclared;` - Declares a class without defining its body
- `node AbstractNode;` - Declares a node without defining its body

Lines 46-50 provide the implementation for `ForwardDeclared` using an `impl` block. The `impl` keyword introduces the implementation, where methods and members can be added. Line 47-49 defines an `info` method.

Lines 52-56 similarly provide the implementation for `AbstractNode` with its own `info` method.

This pattern allows for separating interface declarations from implementations, which is useful for forward references, organizing code, and creating abstract interfaces that will be implemented later.

**Archetype Comparison**

| Archetype | Keyword | OSP Role | Purpose |
|-----------|---------|----------|---------|
| Object | `obj` | Core OSP archetype | Backward compatibility with OOP concepts |
| Node | `node` | Core OSP archetype | Entities that can be connected via edges and host walkers |
| Edge | `edge` | Core OSP archetype | First-class relationships that carry data and behavior |
| Walker | `walker` | Core OSP archetype | Autonomous computation that traverses node-edge structures |
| Class | `class` | Compatibility layer | Traditional Python/OOP classes (not an OSP archetype) |

**Key Features Demonstrated**

- All archetypes support inheritance (single and multiple)
- Decorators can be applied to archetype declarations
- Access modifiers (`:priv`, `:pub`, `:protect`) control visibility
- Forward declarations enable separation of interface and implementation
- The `async` keyword enables asynchronous capabilities
- The `impl` block pattern allows incremental definition of archetype members
