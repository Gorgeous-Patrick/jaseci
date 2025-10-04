Literal patterns are the simplest form of pattern matching, allowing you to match against specific constant values like numbers, strings, or booleans.

**Basic Literal Matching**

Lines 6 and 8 demonstrate literal patterns matching against integer values. The match statement on line 5 evaluates the expression `num` and compares it against each case's literal pattern. Line 6 contains the pattern `case 89:`, which matches when `num` equals exactly `89`. Since `num` is set to `89` on line 4, this case matches and executes line 7, printing `"Correct"`.

**Match Evaluation Order**

Match statements evaluate cases sequentially from top to bottom and execute the first matching case. Once a match is found, no further cases are evaluated. In this example, if `num` were `8`, the first case (line 6) would not match, but the second case (line 8) would match and execute line 9.

**Literal Types**

Literal patterns can match various constant types:
- **Integers**: `case 89:`, `case 0:`, `case -5:`
- **Floats**: `case 3.14:`, `case -0.5:`
- **Strings**: `case "hello":`, `case 'world':`
- **Booleans**: `case True:`, `case False:`
- **None**: `case None:`

The value being matched must be equal to the literal value using value equality (similar to the `==` operator). For numbers, this means the numeric value must match. For strings, the string contents must be identical.
