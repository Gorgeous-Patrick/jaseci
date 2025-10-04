Control statements in Jac alter the normal sequential flow of execution within loops and walker traversals, providing mechanisms to skip iterations or exit loops early.

**Break Statement**

The `break` keyword immediately exits the innermost enclosing loop.

Lines 5-11 demonstrate `break` in a `for` loop:
- Loop iterates through `range(9)` (0 through 8)
- When `i > 2` (line 6), the `break` statement executes (line 8)
- Loop terminates immediately, skipping remaining iterations
- Only 0, 1, and 2 are printed before the loop exits

Lines 30-37 show `break` in a `while` loop:
- Loop runs indefinitely (`while True`)
- Counter increments each iteration
- When `count > 5`, `break` exits the loop
- Prevents infinite loop by providing an exit condition

**Continue Statement**

The `continue` keyword skips the rest of the current iteration and proceeds to the next iteration.

Lines 14-19 demonstrate `continue` in a string iteration:
- Loop iterates over characters in "WIN"
- When `j == "W"` (line 15), `continue` executes (line 16)
- Skips the print statement for "W"
- Only "I" and "N" are printed

Lines 40-47 show `continue` with a conditional filter:
- Loop counts from 1 to 10
- When `n % 2 == 0` (even numbers), `continue` skips the print
- Only odd numbers are printed

**Skip Statement**

Lines 22-27 mention the `skip` keyword, which is Jac-specific for walker traversal contexts. Unlike `continue`, which skips loop iterations, `skip` is used within walker abilities to skip processing of the current node or edge during graph traversal.

**Nested Loops with Break**

Lines 50-58 demonstrate `break` in nested loops:
- Outer loop iterates `x` through 0, 1, 2
- Inner loop iterates `y` through 0, 1, 2
- When both `x == 1` and `y == 1` (line 52), inner loop breaks
- `break` only exits the inner loop, not the outer loop
- Outer loop continues with next `x` value

**Control Statement Scope**

Important semantics:
- `break` and `continue` only affect the innermost enclosing loop
- Cannot break/continue across function boundaries
- Used only within `for`, `while`, and similar loop constructs
- `skip` has special meaning in walker contexts

**Common Patterns**

| Pattern | Use Case | Lines |
|---------|----------|-------|
| Break on condition | Early exit when goal reached | 5-11, 30-37 |
| Continue to filter | Skip unwanted items | 14-19, 40-47 |
| Nested loop break | Exit only inner loop | 50-58 |

Control statements enable more expressive loop logic, avoiding deeply nested conditionals and enabling early termination of unnecessary iterations.