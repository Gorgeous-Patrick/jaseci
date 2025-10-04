This example demonstrates the while loop construct in Jac, including basic iteration, the else clause for normal completion, and interaction with control flow statements.

**Basic While Loop**

Lines 5-9 show the fundamental while loop syntax. The loop continues executing as long as the condition `x < 5` evaluates to true. Line 8 increments `x` by 1 in each iteration. This loop will print 0, 1, 2, 3, 4 before the condition becomes false and the loop exits. Unlike for loops, while loops require manual management of the loop variable.

**While with Else Clause**

Lines 12-18 demonstrate the while-else construct, similar to the for-else pattern. The else block on lines 16-17 executes when the loop condition becomes false naturally (i.e., when `count` reaches 3 and the condition `count < 3` evaluates to false). The else clause will print "While loop completed normally" after printing "Count: 0", "Count: 1", and "Count: 2".

**While with Break**

Lines 21-30 illustrate how the `break` statement affects the else clause. When `break` is executed on line 24 (when `i == 5`), the loop terminates immediately and jumps past both the remaining loop body and the else clause. The else block on lines 28-29 is skipped entirely. This behavior makes the else clause useful for distinguishing between normal loop completion and early termination.

**Control Flow Semantics**

The while loop evaluates its condition before each iteration:
1. The condition is checked
2. If true, the loop body executes
3. After the body completes, control returns to step 1
4. If false, control moves to the else clause (if present) or continues after the loop
5. If `break` is encountered, the loop and else clause are both skipped

**Comparison with For Loops**

| Feature | While Loop | For Loop |
|---------|------------|----------|
| Condition check | Explicit boolean expression | Implicit iteration completion |
| Counter management | Manual | Automatic |
| Use case | Condition-based loops | Collection/range iteration |
| Else clause | Executes on normal completion | Executes on normal completion |
| Break behavior | Skips else clause | Skips else clause |

**Common Patterns**

- Use while loops when the number of iterations is not known in advance
- Use for loops when iterating over collections or known ranges
- The else clause is useful for search loops where you want to know if a condition was ever met
- Always ensure the loop condition will eventually become false to avoid infinite loops
