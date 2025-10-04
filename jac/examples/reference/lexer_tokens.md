Lexer tokens for builtin types are keywords in Jac that represent fundamental data types, used primarily in type annotations.

**Builtin Type Keywords**

Lines 7-14 demonstrate the builtin type keywords used as type annotations:

| Keyword | Type | Example Value |
|---------|------|---------------|
| `str` | String | "string" |
| `int` | Integer | 42 |
| `float` | Float | 3.14 |
| `list` | List | [1, 2, 3] |
| `tuple` | Tuple | (1, 2) |
| `set` | Set | {1, 2} |
| `dict` | Dictionary | {"key": "value"} |
| `bool` | Boolean | True |

**Type Annotation Syntax**

The pattern is `variable: type = value`:
- `x: str = "string"` - declares x as a string
- `y: int = 42` - declares y as an integer
- And so on for each type

**Lexer Treatment**

These keywords are tokenized specially by the lexer so they can serve dual purposes:
1. As type annotations (compile-time type information)
2. As runtime type objects (when used as values)

**Usage Context**

These tokens appear in:
- Variable declarations (lines 7-14)
- Function parameter annotations
- Function return type annotations
- Class attribute declarations

**Note**

Line 18 points to `builtin_types.jac` for more comprehensive examples of type usage. This file focuses specifically on the lexer-level recognition of these keywords as special tokens representing the builtin type system.