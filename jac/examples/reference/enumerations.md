Enumerations in Jac provide a way to define named constants with associated values, supporting forward declarations, decorators, access control, and embedded code blocks.

**Forward Declaration with Decorator**

Lines 6-7 show enum forward declaration: `@unique enum Color;`. The `@unique` decorator (imported from Python's enum module) ensures all enum values are distinct. The semicolon indicates forward declaration - the enum body comes later.

**Enum Implementation**

Lines 10-14 use an `impl` block to define the Color enum's members:
- RED = 1
- GREEN = 2
- BLUE = 3

This two-step approach (declare then implement) allows decorators to be applied before the body is defined.

**Inline Enum Definition with Access Tag**

Lines 17-29 demonstrate a complete enum definition with access control:
- `:protect` is an access tag restricting visibility
- Members use string values: `'admin'`, `'user'`, `'guest'`
- The enum body can contain free code (lines 23-28)

**Free Code in Enum Blocks**

Lines 23-28 show that enum bodies can include executable code:
- `with entry` block runs when the enum is initialized
- Functions can be defined within the enum (lines 25-27)
- These become enum-level methods accessible via `Role.foo()`

**Trailing Commas**

Lines 32-36 show the Status enum with trailing commas in the assignment list. Trailing commas are allowed and useful for version control, as they let you add new members without modifying existing lines.

**Python Code Blocks in Enums**

Lines 39-48 demonstrate embedding Python code using `::py::` delimiters:
- The Priority enum has a custom Python method `get_priority_name`
- This method has access to `self` and enum member attributes
- Python code can define methods that integrate with Jac enum functionality

**Accessing Enum Values**

Line 58 shows two ways to access enum data:
- `Color.RED.value` accesses the numeric value (1)
- `Role.foo()` calls the function defined in the enum's free code block

Line 59 demonstrates that enum members can be printed directly: `Status.ACTIVE` displays the enum member.

**Enum Syntax Patterns**

| Pattern | Lines | Purpose |
|---------|-------|---------|
| Forward declaration | 6-7 | Apply decorators before body |
| Impl block | 10-14 | Define enum members separately |
| Inline with access tag | 17-21 | Control visibility |
| Free code blocks | 23-28 | Add initialization logic |
| Python code blocks | 44-47 | Define Python-specific methods |
| Trailing commas | 32-36 | Version control friendly |

**Inheritance** (lines 51-55, commented)

The commented section suggests potential support for enum inheritance, allowing enums to extend base classes, though this may be implementation-specific.

Enumerations in Jac are more powerful than simple constants, supporting methods, initialization code, and integration with both Jac and Python semantics.