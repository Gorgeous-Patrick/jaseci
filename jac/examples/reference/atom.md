Atoms are the most fundamental building blocks of Jac expressions, representing literals, names, and basic value constructs.

**String Literals**

Lines 12-13 demonstrate basic string literals using double quotes: `a = "abcde...."`. Strings can contain any sequence of characters.

Lines 79-80 show multistring concatenation where adjacent string literals are automatically concatenated: `"Hello " "World"` becomes `"Hello World"`.

Lines 83-85 demonstrate f-strings (formatted string literals) using the `f` prefix: `f"Hello {name}"`. Expressions within curly braces are evaluated and inserted into the string. Line 5 shows a more complex f-string embedded within an impl block.

**Boolean Literals**

Lines 16-18 show the two boolean literals: `True` and `False`. These are case-sensitive keywords representing boolean values.

**None Literal**

Lines 21-22 demonstrate the `None` literal, which represents the absence of a value (similar to null in other languages).

**Integer Literals**

Jac supports multiple integer literal formats:

| Format | Prefix | Example | Line | Decimal Value |
|--------|--------|---------|------|---------------|
| Decimal | None | `42` | 25 | 42 |
| Binary | `0b` | `0b1100` | 29 | 12 |
| Octal | `0o` | `0o755` | 33 | 493 |
| Hexadecimal | `0x` | `0xFF` | 37 | 255 |

All integer formats are case-insensitive for their prefixes (e.g., `0xFF` and `0xff` are equivalent).

**Float Literals**

Lines 41-43 demonstrate floating-point literals:
- Standard decimal notation: `3.14`
- Scientific notation: `1.5e10` represents 1.5 × 10¹⁰

**Ellipsis Literal**

Lines 46-47 show the ellipsis literal `...`, which is used in various contexts like slice notation or as a placeholder value.

**Parenthesized Expressions**

Lines 50-51 demonstrate that any expression can be wrapped in parentheses to control evaluation order: `(5 + 3) * 2`. The parentheses ensure addition occurs before multiplication.

Lines 54-56 (commented) show that yield expressions can be parenthesized when used in certain contexts.

**Named References**

Lines 59-60 show simple variable references. A name like `variable_name` refers to the value bound to that variable.

**Type References**

Lines 63-65 (commented) mention type references using backtick notation like `` `str `` and `` `int ``, though this syntax may be implementation-specific.

Lines 68-70 show that builtin type names can be used as values: `string_type = str` assigns the type object itself to a variable.

**Collection Literals**

Lines 73-76 demonstrate collection literals:
- Tuple: `(1, 2, 3)` - immutable sequence
- List: `[1, 2, 3]` - mutable sequence
- Dictionary: `{"key": "value"}` - key-value mapping
- Set: `{1, 2, 3}` - unordered collection of unique values

Line 8 shows global collection definitions.

**Impl Blocks with Atoms**

Lines 3-6 show an `impl` block that can contain atom expressions, including computed f-string values.

**Enum Usage**

Lines 87-88 demonstrate enum declaration and accessing enum member values using dot notation: `x.y.value`.