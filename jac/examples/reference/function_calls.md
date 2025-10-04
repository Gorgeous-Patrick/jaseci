Function calls in Jac support positional arguments, keyword arguments, and expressions as arguments, providing flexible ways to pass data to functions.

**Function Definition**

Lines 3-5 define a function `foo` that takes three integer parameters and returns a tuple: `return (x * y, y * z)`.

**Keyword Arguments**

Line 11 demonstrates keyword arguments: `foo(x=4, y=4 if a % 3 == 2 else 3, z=9)`. Each argument is specified by parameter name, allowing:
- Arguments in any order
- Clear intent for each value
- Expressions as argument values (the ternary expression for `y`)

**Positional Arguments**

Lines 15-16 show positional arguments: `foo(1, 2, 3)`. Arguments are matched to parameters by position - first argument goes to `x`, second to `y`, third to `z`. This is the most concise form when argument order is obvious.

**Mixed Positional and Keyword Arguments**

Lines 19-20 demonstrate mixing both styles: `foo(1, y=2, z=3)`. Rules for mixing:
- Positional arguments must come first
- Keyword arguments follow positionals
- Once you use a keyword argument, all subsequent arguments must be keywords
- First positional (1) maps to `x`, then `y` and `z` are specified by name

This flexibility allows calling the same function in different styles depending on clarity needs.