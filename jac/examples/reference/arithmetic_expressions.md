Arithmetic expressions in Jac follow standard mathematical operator precedence and associativity rules, supporting a comprehensive set of numeric operations.

**Basic Binary Operators**

Jac supports the standard arithmetic operators with the following precedence (from highest to lowest):

| Operator | Description | Example (lines) |
|----------|-------------|-----------------|
| `**` | Exponentiation | Line 11 |
| `*` | Multiplication | Line 7 |
| `/` | Division (float result) | Line 8 |
| `//` | Floor division (integer result) | Lines 9, 40 |
| `%` | Modulo (remainder) | Lines 10, 41 |
| `+` | Addition | Line 12 |
| `-` | Subtraction | Line 13 |

Lines 7-13 demonstrate each basic arithmetic operation in isolation. Note that division `/` always produces a float result, while floor division `//` produces an integer by truncating toward negative infinity.

**Operator Precedence and Grouping**

Line 16 shows how parentheses override default precedence: `(9 + 2) * 9 - 2`. Without parentheses, multiplication would execute before addition. The expression evaluates as `11 * 9 - 2 = 97`.

Line 32 demonstrates a complex expression with mixed operators: `2 + 3 * 4 ** 2 - 10 / 2`. Following precedence rules:
1. Exponentiation first: `4 ** 2 = 16`
2. Multiplication and division: `3 * 16 = 48` and `10 / 2 = 5.0`
3. Addition and subtraction: `2 + 48 - 5.0 = 45.0`

**Unary Operators**

Lines 19-22 demonstrate unary prefix operators:

- `+x` (line 20): Unary plus, returns the numeric value unchanged
- `-x` (line 21): Unary minus, negates the value
- `~x` (line 22): Bitwise NOT, inverts all bits in the integer representation

These unary operators have higher precedence than binary operators.

**Exponentiation Associativity**

Line 25 highlights that exponentiation is right-associative: `2 ** 3 ** 2` evaluates as `2 ** (3 ** 2) = 2 ** 9 = 512`, not `(2 ** 3) ** 2 = 8 ** 2 = 64`.

**Matrix Multiplication**

Lines 27-29 mention the matrix multiplication operator `@`, though it requires matrix types and isn't demonstrated with executable code. This operator has the same precedence as regular multiplication.

**Chained Operations**

Lines 36-37 show that operators of the same precedence are left-associative:
- `100 - 50 + 25` evaluates as `(100 - 50) + 25 = 75`
- `2 * 3 * 4` evaluates as `(2 * 3) * 4 = 24`

**Floor Division and Modulo**

Lines 40-41 demonstrate the relationship between floor division and modulo:
- `17 // 5 = 3` (quotient)
- `17 % 5 = 2` (remainder)

Together they satisfy: `17 = 5 * 3 + 2`