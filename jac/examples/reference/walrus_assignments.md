The walrus operator `:=` enables assignment within expressions, allowing you to assign values and use them in the same statement. This operator is also known as the "assignment expression" operator.

**Walrus in If Conditions**

Lines 5-9 demonstrate using the walrus operator in an if statement. Line 6 shows `if (b := a + a // 2) > 5`, which:
1. Evaluates `a + a // 2` (which is `5 + 5 // 2 = 5 + 2 = 7`)
2. Assigns the result to `b`
3. Tests if `b > 5` (which is true)
4. Makes `b` available in the if block and beyond

Without the walrus operator, you'd need two statements: `b = a + a // 2; if b > 5 { ... }`. The walrus combines these into one line while making the assignment's result available for both the condition and the body (line 8).

**Walrus in While Loops**

Lines 12-20 demonstrate the walrus operator in a while loop condition. Line 14 shows:
```
while (item := data[i] if i < len(data) else None) { ... }
```

This assigns and tests in one expression:
1. Evaluates the ternary expression: `data[i] if i < len(data) else None`
2. Assigns the result to `item`
3. Tests the truthiness of `item` (None is falsy, ending the loop)
4. Makes `item` available in the loop body (line 15)

This pattern is useful for loops that process items until a sentinel value appears.

**Walrus in Comprehensions (Currently Limited)**

Lines 23-25 show a commented-out list comprehension with walrus: `[y for x in values if (y := x * 2) > 4]`. This would:
1. Iterate through values
2. For each x, assign `x * 2` to y
3. Filter by `y > 4`
4. Collect the y values

The TODO comment indicates this usage may not be fully supported yet.

**Walrus in Expressions**

Lines 28-29 demonstrate walrus in a regular expression. Line 28 shows `result = (x := 10) + 5`, which:
1. Assigns 10 to `x`
2. Evaluates to 10 (the assigned value)
3. Adds 5 to get 15
4. Assigns 15 to `result`

After this, `x` is 10 and `result` is 15. The walrus operator returns the value being assigned, allowing it to participate in further calculations.

**Multiple Walrus Assignments**

Lines 32-34 show multiple walrus operators in a single condition: `if (m := 5) and (n := 10)`. This:
1. Assigns 5 to `m`, which evaluates to 5 (truthy)
2. Assigns 10 to `n`, which evaluates to 10 (truthy)
3. Tests `5 and 10`, which is true
4. Makes both `m` and `n` available in the if block and beyond

Both variables retain their values after the if statement.

**Parentheses Requirement**

The walrus operator typically requires parentheses to avoid ambiguity. For example:
- `if (x := 5) > 3:` is correct
- `if x := 5 > 3:` would be ambiguous

Parentheses clarify that you're assigning 5 to x, then comparing x to 3, rather than assigning `5 > 3` to x.

**Scope Rules**

Variables assigned with the walrus operator are scoped to the enclosing function or module, not just the expression or block where they appear. In the examples:
- `b` from line 6 is accessible after the if block
- `item` from line 14 is accessible after the while loop
- `x`, `m`, and `n` are all accessible after their respective statements

**Use Cases**

The walrus operator is particularly useful for:
- **Avoiding duplication**: Compute a value once and use it in multiple places
- **Loop conditions**: Assign and test in while loop conditions
- **Complex conditions**: Compute intermediate values in if statements
- **Readability**: Make assignment and usage explicit in a single expression

**Common Patterns**

| Pattern | Use Case | Example |
|---------|----------|---------|
| If condition | Test computed value | `if (x := compute()) > threshold` |
| While loop | Process until sentinel | `while (line := file.readline())` |
| Expression | Reuse computed value | `result = (n := expensive()) * 2 + n` |
| Multiple assignments | Initialize multiple values | `if (a := 1) and (b := 2)` |

**Comparison to Regular Assignment**

Unlike regular assignment (=), the walrus operator:
- Can be used within expressions
- Returns the assigned value
- Works in conditions, comprehensions, and other expression contexts
- Is an expression itself, not a statement
