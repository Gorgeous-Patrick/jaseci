This example demonstrates the various forms and patterns of conditional statements in Jac, including if-elif-else chains, nested conditions, and different conditional structures.

**Basic If-Elif-Else Structure**

Lines 7-13 show the complete conditional structure with all three clauses. The condition `0 <= x <= 5` uses Python-style chained comparisons to check if `x` is between 0 and 5 (inclusive). When the first condition is false, execution moves to the `elif` clause on line 9, checking if `x` is between 6 and 10. If both conditions are false, the `else` clause on line 11 executes. Since `x = 15`, the output will be "Good Enough".

**If Without Else/Elif**

Lines 16-18 demonstrate a standalone `if` statement with no alternative clauses. The condition simply checks if `x > 0` and prints "Positive" if true. This is useful when you only need to perform an action when a condition is met, with no alternative behavior needed.

**If-Elif Without Else**

Lines 21-25 show an if-elif chain without a final `else` clause. This structure is useful when you want to check multiple conditions but don't need a default action if all conditions fail. In this example, neither condition is true (since `x = 15`), so nothing is printed.

**Multiple Elif Chains**

Lines 28-38 demonstrate a more complex conditional ladder with multiple `elif` clauses. This creates a series of mutually exclusive conditions that are evaluated in order from top to bottom. The first condition that evaluates to true will have its code block executed, and subsequent conditions are skipped. Since `x = 15`, the condition `x < 15` on line 32 is false, but `x < 20` on line 34 is true, so "High" is printed.

**Nested If Statements**

Lines 41-47 show if statements nested within other if statements. The outer if on line 41 checks if `x > 10`. If true, the inner if on line 42 checks if `x > 20`. This creates hierarchical conditional logic. Since `x = 15`, the outer condition is true but the inner condition is false, resulting in "Between 10 and 20" being printed.

**Syntax Notes**

- Conditions are evaluated as boolean expressions
- Code blocks are delimited with curly braces `{}`
- Chained comparisons like `0 <= x <= 5` are supported (Python-style)
- Multiple `elif` clauses can be chained together
- Both `elif` and `else` clauses are optional
- Only the first matching condition's block is executed in an if-elif-else chain
