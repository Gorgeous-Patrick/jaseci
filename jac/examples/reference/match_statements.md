Match statements provide a powerful pattern matching construct for handling different data structures and values in a declarative way. They offer a more expressive alternative to chains of if-elif-else statements.

**Basic Match Structure**

Lines 7-12 show the fundamental structure of a match statement. The `match` keyword on line 7 is followed by an expression to match against (`a` in this case). The body contains one or more `case` clauses, each with a pattern and associated code. The match statement evaluates the expression once, then checks each case pattern in order until one matches.

Line 8 demonstrates a literal pattern `case 7:`, which matches when `a` equals `7`. Since `a` is `8`, this case doesn't match. Line 10 shows the wildcard pattern `case _:`, which matches any value and serves as a default case, executing line 11.

**Guard Clauses**

Lines 15-23 demonstrate match statements with guard clauses using the `if` keyword. A guard clause is a boolean condition that must be true for the pattern to match. Line 17 shows `case x if x < 10:`, which binds the matched value to `x` and then checks if `x < 10`. This provides additional filtering beyond just pattern structure.

Guard clauses are evaluated only after the pattern matches successfully. The variable bound in the pattern (in this case `x`) is available in the guard condition. Multiple cases can have guard clauses, and they are evaluated in order. In this example, since `value` is `15`, line 17's guard fails but line 19's guard `x < 20` succeeds, executing line 20.

**Multiple Statements in Case Bodies**

Lines 26-39 show that case bodies can contain multiple statements. Unlike some languages that require explicit fall-through prevention, Jac's match statements automatically exit after executing a matching case's body. Lines 28-31 demonstrate this with three statements executed when the pattern matches: two print statements and a variable assignment. There's no need for a `break` statement - execution continues after the entire match block.

**Complex Patterns with Sequences**

Lines 42-55 demonstrate matching against sequence patterns of different lengths. Line 47 matches a single-element list with `case [x]:`, capturing the element in variable `x`. Line 49 matches a two-element list with `case [x, y]:`, and line 51 matches a three-element list with `case [x, y, z]:`. Each pattern extracts the elements into named variables that can be used in the case body.

Since `data` is `[1, 2, 3]` on line 42, the pattern on line 51 matches and executes line 52, printing `"Three elements: 1, 2, 3"`. The comment on lines 44-46 notes a current limitation with empty list patterns.

**Match Semantics**

Key semantic points about match statements:
- Patterns are evaluated sequentially from top to bottom
- Only the first matching case executes
- After a case executes, control flow exits the match statement
- The wildcard pattern `_` matches anything and is typically used as the last case
- Variables bound in patterns are only available within their case body
- Guard clauses provide additional boolean filtering after pattern matching
