Return statements exit a function or method and optionally send a value back to the caller. They are fundamental to function-based programming and control flow.

**Return with Expression**

Lines 3-6 demonstrate returning a value from a function. Line 5 shows `return a;`, which exits the `foo` function and sends the value of variable `a` (42) back to the caller. The function signature on line 3 includes `-> int`, indicating the function returns an integer type.

Line 30 calls `foo()` and prints the returned value, demonstrating how the caller receives the value specified in the return statement.

**Return without Expression**

Lines 8-12 demonstrate a return statement without a value. Line 11 shows `return;` with no expression, which exits the function and implicitly returns `None`. This is useful when you want to exit a function early without providing a return value.

Functions without an explicit return type annotation (like `bar` on line 8) can return `None` or any value. The bare `return;` is equivalent to `return None;`.

**Conditional Returns**

Lines 14-20 show using return statements in conditional branches. Line 16 returns `x * 2` when `x > 0`, while line 18 returns `0` otherwise. This pattern ensures that all code paths through the function return a value, which is important when the function has a return type annotation.

When the function is called with `get_value(5)` (line 32), it takes the first branch and returns 10. When called with `get_value(-3)` (line 33), it takes the else branch and returns 0.

**Early Return Pattern**

Lines 22-27 demonstrate the early return pattern for flow control. Line 24 shows `return;` used to exit the function early when a condition is met. If `flag` is `True`, the function returns immediately and line 26 never executes. This pattern is useful for:
- Guard clauses that validate inputs
- Handling special cases before main logic
- Avoiding deep nesting in conditional logic
- Simplifying complex control flow

Line 34 calls `early_return(True)`, which returns immediately without printing. Line 35 calls `early_return(False)`, which skips the early return and prints the message.

**Return Statement Semantics**

Key behaviors of return statements:
- **Immediate exit**: Execution stops at the return statement; no subsequent code in the function runs
- **Value passing**: The expression value is evaluated and passed to the caller
- **Type checking**: Return values should match the function's return type annotation
- **Implicit None**: Functions without an explicit return statement implicitly return `None`
- **Single return**: Unlike `report` statements in walkers, `return` can only execute once per function call

**Return Type Annotations**

The examples show different return type annotation styles:
- `def foo -> int` (line 3): Returns an int
- `def bar` (line 8): No return type specified (implicitly returns None or any)
- `def get_value(x: int) -> int` (line 14): Explicit parameter and return types
- `def early_return(flag: bool)` (line 22): No return type (returns None)

**Common Patterns**

Return statements enable several common programming patterns:
1. **Value computation**: Calculate a result and return it (line 5)
2. **Early exit**: Return early from guard clauses (line 24)
3. **Branching logic**: Return different values based on conditions (lines 16, 18)
4. **Explicit None**: Use bare `return;` to exit without a value (line 11)
