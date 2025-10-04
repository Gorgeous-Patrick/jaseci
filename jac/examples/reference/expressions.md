This example demonstrates ternary conditional expressions in Jac, which provide inline conditional logic for selecting between two values based on a boolean condition.

**Basic Ternary Expression**

Line 5 shows the ternary syntax: `x = 1 if 5 / 2 == 1 else 2`. The format is:

`value_if_true if condition else value_if_false`

This evaluates:
- The condition `5 / 2 == 1` (false, since 5 / 2 = 2.5)
- Returns the `else` value: 2
- Assigns 2 to x

**Practical Ternary Usage**

Lines 9-11 show a common pattern for conditional assignment:
- `age = 20`
- `status = "adult" if age >= 18 else "minor"`
- Since age >= 18 is true, status becomes "adult"

This is more concise than an if-else statement when you just need to pick between two values.

**Nested Ternary Expressions**

Lines 14-16 demonstrate nesting ternaries for multiple conditions:

`grade = "A" if score >= 90 else ("B" if score >= 80 else "C")`

This evaluates left-to-right:
1. If score >= 90: return "A"
2. Else if score >= 80: return "B"
3. Else: return "C"

With score = 85, this returns "B".

Note: Nested ternaries can become hard to read. For more than 2-3 conditions, traditional if-elif-else statements are clearer.

**Ternary with Function Calls**

Lines 19-20 show that any expression works in ternary branches:

`value = max(10, 20) if True else min(10, 20)`

Since the condition is True, this calls `max(10, 20)` and assigns 20 to value. The `min()` call never executes - ternaries evaluate only the selected branch.

**Ternary vs If-Statement**

Ternaries are best for:
- Simple conditional assignments
- Inline conditional values in expressions
- Reducing code verbosity for binary choices

Use if-statements when:
- You need multiple statements per branch
- Conditions are complex
- Readability would suffer from nesting

**Evaluation Order**

The ternary operator evaluates:
1. The condition
2. Only the selected branch (lazy evaluation)
3. Returns the branch's value

This means side effects only occur in the executed branch.