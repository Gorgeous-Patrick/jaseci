This example showcases the different forms of for loops available in Jac, including Python-style iteration, C-style loops, and special features like else clauses and nested loops.

**For-In Loop (Python-Style)**

Lines 5-7 demonstrate the basic for-in loop syntax, which iterates over any iterable object. Here, the loop iterates over each character in the string "ban", printing 'b', 'a', and 'n' in sequence. This is the most common loop form for iterating over collections.

**For-In with Range**

Lines 10-12 show a for-in loop using the `range()` function. The call `range(1, 3)` generates values 1 and 2 (the end value 3 is exclusive). This is useful for iterating a specific number of times with numeric indices.

**For-To-By Loop (C-Style)**

Lines 15-17 introduce Jac's unique C-style for loop syntax: `for k=1 to k<3 by k+=1`. This consists of three parts:
- Initialization: `k=1` sets the starting value
- Condition: `to k<3` defines when the loop continues
- Increment: `by k+=1` specifies how to update the variable after each iteration

This form provides explicit control over the loop counter and is reminiscent of C's `for(int k=1; k<3; k++)` but with more readable syntax.

**For-Else Clause**

Lines 20-24 demonstrate the for-else construct, borrowed from Python. The `else` clause executes when the loop completes normally (reaches the end of the iterable without encountering a `break` statement). After iterating through [1, 2, 3], the else block prints "For loop completed".

**For with Break**

Lines 27-34 show how `break` affects the else clause. When `break` is executed (line 29 when num equals 5), the loop terminates immediately and the else clause is skipped. This makes the else clause useful for detecting whether a loop completed all iterations versus being interrupted early.

**Async For Loop**

Lines 36-39 show commented-out syntax for asynchronous iteration using `async for`. This would be used with asynchronous iterables to await values as they become available, supporting concurrent programming patterns.

**Nested For Loops**

Lines 42-48 demonstrate multiple levels of loop nesting, combining all three for loop styles:
- Outer loop iterates over characters in "ban"
- Middle loop uses range(1, 3)
- Inner loop uses the for-to-by syntax

Each combination of (i, j, k) is printed, demonstrating that all loop types can be freely nested and combined.

**Summary of For Loop Forms**

| Form | Syntax | Use Case |
|------|--------|----------|
| for-in | `for var in iterable { }` | Iterating over collections |
| for-in range | `for var in range(start, end) { }` | Numeric iteration |
| for-to-by | `for var=init to condition by increment { }` | Explicit counter control |
| with else | `for ... { } else { }` | Detecting normal completion |
| async for | `async for var in async_iterable { }` | Asynchronous iteration |

**Control Flow Notes**

- `break` exits the loop immediately and skips the else clause
- `continue` (not shown) skips to the next iteration
- The else clause only executes on normal loop completion
- All loop forms can be nested arbitrarily
