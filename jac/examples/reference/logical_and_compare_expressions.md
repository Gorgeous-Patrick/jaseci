Jac provides a comprehensive set of operators for comparing values, testing identity and membership, and combining boolean expressions.

**Comparison Operators**

Lines 5-27 demonstrate the six comparison operators available in Jac. These operators evaluate to boolean values and are used to compare numeric values, strings, and other comparable types:

| Operator | Meaning | Example (Line) |
|----------|---------|----------------|
| `>` | Greater than | Line 5: `5 > 4` |
| `>=` | Greater than or equal to | Line 9: `5 >= 5` |
| `<` | Less than | Line 13: `3 < 10` |
| `<=` | Less than or equal to | Line 17: `3 <= 3` |
| `==` | Equal to | Line 21: `5 == 5` |
| `!=` | Not equal to | Line 25: `"a" != "b"` |

These operators work with any comparable types, including numbers, strings, and other objects that implement comparison methods.

**Identity Operators**

Lines 29-36 demonstrate identity operators, which test whether two variables refer to the same object in memory rather than whether they have equal values. Line 30-32 set up the example by creating two separate lists `a` and `b` with identical contents, and assigning `c` to reference the same object as `a`.

The `is` operator (line 34-35) checks if two references point to the exact same object. Even though `a` and `b` contain the same values, `a is b` returns `False` because they are different list objects in memory. However, `a is c` returns `True` because both variables reference the same list object.

The `is not` operator (line 36) is the negation of `is`, returning `True` when two references point to different objects.

**Membership Operators**

Lines 38-41 showcase membership operators for testing whether a value exists within a collection. The `in` operator (line 39-40) returns `True` if the left operand is found within the right operand (a collection like a list, tuple, set, or string). The `not in` operator (line 41) is the logical inverse, returning `True` when the value is not found in the collection.

**Logical Operators**

Lines 43-50 demonstrate the three core logical operators used to combine boolean expressions:

- `or` (line 44): Returns `True` if at least one operand is `True`
- `and` (line 45-46): Returns `True` only if both operands are `True`
- `not` (line 49-50): Unary operator that inverts a boolean value

These operators follow short-circuit evaluation semantics. For `or`, if the left operand is `True`, the right operand is not evaluated. For `and`, if the left operand is `False`, the right operand is not evaluated.

**Chained Comparisons**

Lines 52-60 illustrate one of Jac's powerful features: chained comparison operators. Instead of writing `10 < x and x < 20`, you can write `10 < x < 20` (line 54). This creates more readable code and evaluates more efficiently because `x` is only evaluated once. Line 58 shows another chained comparison with inclusive bounds using `<=`.

Chained comparisons work with any combination of comparison operators and are evaluated left-to-right, with each comparison sharing operands with its neighbors.

**Complex Logical Expressions**

Lines 62-74 demonstrate how to combine multiple conditions using logical operators. Line 66 shows an `and` operation combining two conditions that must both be true. Line 70 shows an `or` operation where only one condition needs to be true. These expressions can be arbitrarily complex and follow standard operator precedence where `not` has the highest precedence, followed by `and`, then `or`.

**Chained Logical Operations**

Lines 76-83 show how multiple logical operators of the same type can be chained together. Line 77 chains three `and` operations, which only evaluates to `True` if all operands are `True`. Line 81 chains three `or` operations, which evaluates to `True` if at least one operand is `True`. These chains also benefit from short-circuit evaluation, stopping as soon as the result is determined.
