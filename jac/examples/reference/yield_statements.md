Yield statements transform a regular function into a generator, enabling lazy evaluation and efficient iteration over sequences that would be expensive or impossible to compute all at once.

**Basic Yield Statement**

Lines 3-8 demonstrate the fundamental yield syntax. Instead of returning a single value and terminating, the function yields multiple values one at a time. Lines 4-7 show four yield statements:
- Line 4: `yield "Hello";` - yields a string
- Line 5: `yield 91;` - yields an integer
- Line 6: `yield "Good Bye";` - yields another string
- Line 7: `yield ;` - yields without an expression, producing `None`

When `myFunc()` is called on line 32, it doesn't execute the function body immediately. Instead, it returns a generator object. The function body executes incrementally as values are requested through iteration (lines 33-35).

**Generator Iteration**

Lines 32-35 show how to consume a generator using a for loop. Line 32 creates the generator object `x`, and lines 33-35 iterate over it. Each iteration:
1. Resumes the generator function from where it last yielded
2. Executes until the next yield statement
3. Returns the yielded value
4. Suspends execution, preserving local state

This prints: `Hello`, `91`, `Good Bye`, `None` (each on a separate line).

**Yield in Loops**

Lines 10-14 demonstrate yielding values in a loop, a common pattern for generating sequences. The function yields each number from 0 to n-1. This is memory-efficient because values are generated one at a time rather than building a complete list.

**Yield From**

Lines 16-20 demonstrate the `yield from` statement, which delegates to another generator or iterable. Line 18 shows `yield from number_generator(3);`, which yields all values produced by `number_generator(3)` (0, 1, 2). Line 19 shows `yield from ["a", "b", "c"];`, which yields each element from the list.

`yield from` is equivalent to a loop that yields each value from the sub-generator, but it's more concise and efficient. Lines 37-42 consume this generator, printing: 0, 1, 2, a, b, c.

**Conditional Yield**

Lines 22-28 show yielding based on conditions. The function iterates through items but only yields those that satisfy a condition (even numbers in this case). Line 24 checks `if item % 2 == 0` before yielding. This pattern enables selective generation, filtering values during iteration rather than pre-filtering.

Lines 44-49 demonstrate this, yielding only even numbers from the input list: 2, 4, 6.

**Generator Characteristics**

Generators have several important properties:
- **Lazy evaluation**: Values are computed only when requested
- **State preservation**: Local variables and execution position are maintained between yields
- **Memory efficiency**: Only one value exists in memory at a time
- **One-time iteration**: Once exhausted, a generator cannot be reused (must create a new one)

**Yield vs Return**

| Feature | `yield` | `return` |
|---------|---------|----------|
| Function type | Generator | Regular function |
| Execution | Pauses and resumes | Terminates |
| Values produced | Multiple (or infinite) | Single |
| Memory | One value at a time | All values if returning collection |
| Reusability | Creates new generator each call | Same result each call |

**Use Cases**

Yield statements are particularly useful for:
- **Large datasets**: Processing files or database results line-by-line
- **Infinite sequences**: Generating unlimited values (e.g., Fibonacci numbers)
- **Pipeline processing**: Chaining generators for data transformation
- **Memory optimization**: When you need to iterate but can't fit all values in memory
- **Lazy computation**: Deferring expensive calculations until needed

**Generator Protocol**

Generators implement the iterator protocol:
- `__iter__()`: Returns the generator itself
- `__next__()`: Resumes execution until next yield
- Raises `StopIteration` when function completes without yielding

This allows generators to be used anywhere an iterable is expected: for loops, list comprehensions, `list()`, `sum()`, etc.
