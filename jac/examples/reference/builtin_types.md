Jac provides a comprehensive set of built-in types for representing different kinds of data. Type annotations are optional but recommended for clarity and type checking.

**Numeric Types**

- **float** (line 3): Floating-point numbers with decimal precision. Example: `a: float = 9.2`
- **int** (line 5): Integer numbers without decimal points. Example: `b: int = 44`
- **bool** (line 13): Boolean values `True` or `False`. Example: `f: bool = True`

**Collection Types**

| Type | Description | Example Line | Mutability |
|------|-------------|--------------|------------|
| `list` | Ordered, mutable sequence | 7 | Mutable |
| `tuple` | Ordered, immutable sequence | 11 | Immutable |
| `dict` | Key-value mapping | 9 | Mutable |
| `set` | Unordered collection of unique values | 17 | Mutable |

Lists use square brackets `[2, 4, 6, 10]`, tuples use parentheses `("jaseci", 5, 4, 14)`, dictionaries use braces with key-value pairs `{'name':'john', 'age':28}`, and sets use braces with unique values `{5, 8, 12, "unique"}`.

**String and Binary Types**

- **str** (line 15): Text strings. Example: `g: str = "Jaseci"`
- **bytes** (line 20): Binary data using the `b` prefix. Example: `i: bytes = b"binary data"`

Bytes are immutable sequences of integers in the range 0-255, useful for binary file I/O and network protocols.

**Special Types**

- **any** (line 23): Accepts any value type. Example: `j: any = "can be anything"`. This is useful when a variable needs to hold different types at different times.
- **type** (line 26): Represents type objects themselves. Example: `k: type = str`. This allows storing and manipulating types as first-class values.

**Type Annotations in Functions**

Lines 42-47 demonstrate type annotations on function parameters and return values:

`def typed_func(x: int, y: float, z: str) -> tuple`

The syntax `-> tuple` specifies the return type. Type annotations serve as documentation and enable static type checking tools to catch type errors before runtime.

**Variable Annotations**

Lines 50-55 show type annotations on local variables. These are identical in syntax to global annotations but apply within the function scope.

**Using Types at Runtime**

Lines 29-39 demonstrate that type annotations don't restrict values at runtime - they're primarily for documentation and optional type checking. The `type()` function returns the actual runtime type of a value, which can be printed and inspected.

All type annotations in Jac are optional. Code without annotations is valid but misses the benefits of type documentation and static analysis.