F-strings (formatted string literals) in Jac provide powerful string interpolation, allowing embedded expressions and values within string literals using the `f` prefix.

**Basic F-String Syntax**

Lines 7-8 show basic interpolation: `f"Hello {x} {y} {{This is an escaped curly brace}}"`.
- The `f` prefix marks the string as formatted
- `{x}` and `{y}` evaluate variables and insert their values
- `{{` and `}}` create literal curly braces (escaped)

**Single vs Double Quotes**

Line 11 demonstrates that f-strings work with single quotes: `f'Single quoted: {x} and {y}'`. Both quote styles support the same interpolation features.

**Complex Expressions**

Lines 14-15 show dictionary access within f-strings:
`f"Hello, {person['name']}! You're {person['age']} years old."`

Any valid expression works inside `{}`, including dictionary lookups, function calls, and arithmetic.

**Escaped Braces**

Line 18 shows doubling braces to create literals:
- `{{{{` produces `{{`
- `}}}}` produces `}}`

This is necessary when you want literal curly braces in the output.

**Arithmetic in F-Strings**

Line 21 demonstrates embedded calculations: `f"Calculation: {5 + 3} = {5 + 3}"`. Each `{...}` evaluates independently, so the expression is computed twice.

**Method Calls**

Lines 24-25 show calling methods on objects: `f"Uppercase: {text.upper()}"`. The method executes and its return value is interpolated into the string.

**Conditional Expressions**

Lines 28-29 use ternary expressions: `f"Status: {('Adult' if age >= 18 else 'Minor')}"`. Complex expressions should be parenthesized for clarity.

**Multi-Line F-Strings**

Lines 32-39 demonstrate triple-quoted f-strings:

`f"""
Name: {name}
Score: {score}
Grade: {('A' if score >= 90 else 'B')}
"""`

Multi-line f-strings preserve formatting and indentation, useful for templates or formatted output.

**Escape Sequences**

Lines 42-45 review standard escape sequences that work in both regular and f-strings:
- `\n`: newline
- `\r`: carriage return
- `\t`: tab
- `\f`: form feed

**F-String with String Methods**

Lines 48-49 show combining f-strings with string methods:
`f"{'\n'.join(words)}"` calls `join()` on a newline character, demonstrating that f-string expressions can contain any string operations.

**Nested F-Strings**

Lines 52-53 show f-strings within f-strings: `f"Value is {f'{value}'}"`

While technically possible, nested f-strings are rarely necessary and can reduce readability.

**Format Specifiers** (commented)

Lines 56-57 mention format specifiers like `{pi:.2f}` for controlling number formatting. These may be implementation-specific but follow Python's format specification mini-language for controlling width, precision, and alignment.

**Advantages of F-Strings**

F-strings provide:
- Clear, readable string interpolation
- Full expression evaluation
- Better performance than string concatenation
- Type conversion happens automatically
- Inline computation without temporary variables