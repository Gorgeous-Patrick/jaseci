Archetype bodies in Jac define the internal structure and behavior of objects, classes, nodes, edges, and walkers. The body can contain various member statements that define data fields, methods, nested types, and initialization logic.

**Member Docstrings**

Line 3-4 demonstrate that docstrings can be placed before archetype definitions. The string literal "This is a member docstring" serves as documentation for the Car archetype.

**Has Statements**

The `has` keyword declares instance-level data fields (attributes) for an archetype:

- Lines 9-11: Basic `has` statement with type annotations. Multiple fields can be declared in a single statement, separated by commas and terminated with a semicolon. Here `make`, `model`, and `year` are declared as instance attributes.
- Line 14: The `static has` declaration creates class-level attributes shared across all instances. The `wheels` attribute is set to 4 for all Car instances.
- Line 17: Has statements support access tags using the colon prefix syntax (`:priv`). This marks `internal_id` as a private field with a default value.
- Line 23: The `by postinit` clause indicates that the field will be initialized in the `postinit` method rather than at declaration time.

**Let Statements**

Line 20 shows the `let` keyword as an alternative to `has`. While semantically similar to `has`, `let` is typically used to emphasize immutability or constant-like behavior, though the actual semantics depend on the implementation.

**Postinit Method**

Lines 25-27 define a special `postinit` method that executes after the object is constructed. This is where fields declared with `by postinit` must be initialized. The method has access to `self` and can perform any setup logic.

**Instance and Static Methods**

Archetype bodies can contain method definitions:

- Lines 30-32: A regular instance method `display_car_info` that uses `self` to access instance attributes.
- Lines 34-36: A `static def` creates a class method that doesn't receive a `self` parameter. It accesses the class-level `wheels` attribute via `Car.wheels`.

**Inline Python Code**

Lines 39-42 demonstrate embedding raw Python code within a Jac archetype using the `::py::` delimiters. Code between these markers is treated as native Python and can define Python-specific methods or logic.

**Nested Archetypes**

Lines 45-47 show that archetypes can be nested within other archetypes. The `Engine` class is defined inside the `Car` object, creating a logical grouping of related types.

**Member-Level Entry Points**

Lines 50-52 demonstrate that `with entry` blocks can appear within archetype bodies, not just at module level. This entry code executes when certain conditions are met (implementation-specific).

**Instantiation and Usage**

Lines 56-58 show how to instantiate the Car archetype and call its methods. The constructor accepts positional arguments for the declared fields, and methods are called using dot notation.