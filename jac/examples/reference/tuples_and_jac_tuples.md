Jac supports both Python-style tuples and a unique named tuple syntax that integrates with the pipe operator for cleaner function calls.

**Python-Style Tuples**

Lines 9-10 demonstrate traditional Python tuple syntax. Line 9 shows `(3, )` - the trailing comma is required for single-element tuples to distinguish them from parenthesized expressions. The expression `(3, ) + (4, )` concatenates two single-element tuples to create `(3, 4)`.

Line 10 creates a tuple by evaluating expressions: `(val1[0] * val1[1], val1[0] + val1[1])`. Since `val1` is `(3, 4)`, this evaluates to `(12, 7)` where:
- First element: `3 * 4 = 12`
- Second element: `3 + 4 = 7`

Line 18 shows a simple tuple literal: `(1, 2, 3)` creates a three-element tuple.

**Jac Named Tuples with Pipe Operator**

Lines 14-15 demonstrate Jac's named tuple syntax combined with the pipe operator. This syntax allows you to specify argument names inline within tuple syntax, then pipe the tuple to a function.

Line 14: `(second=val2[1], first=val2[0]) |> foo`
- Creates a named tuple with `second=7` and `first=12`
- Pipes it to function `foo`, which has parameters `(first: int, second: int)`
- The named tuple maps to function parameters by name, not position
- This calls `foo(first=12, second=7)`, printing `12 7`

Line 15: `(first=val2[0], second=val2[1]) |> foo`
- Creates a named tuple with `first=12` and `second=7`
- When piped to `foo`, maps directly to parameters
- This calls `foo(first=12, second=7)`, printing `12 7`

**Order Independence**

The key feature of named tuples is that argument order doesn't matter. Notice line 14 specifies `second` before `first`, but because the names are explicit, the function receives the correct values in the correct parameters. Both lines 14 and 15 produce the same output despite different ordering in the tuple.

**Function Definition**

Lines 3-5 define the target function `foo(first: int, second: int)` that receives the piped named tuples. The function expects two integer parameters and prints them.

**Named Tuple Syntax**

The general form of a named tuple is:
`(name1=value1, name2=value2, ...)`

When piped to a function:
`(name1=value1, name2=value2) |> function_name`

This is equivalent to:
`function_name(name1=value1, name2=value2)`

**Advantages of Named Tuples with Pipe**

This syntax provides several benefits:
- **Clarity**: Argument names are explicit at the call site
- **Order independence**: Arguments can be in any order
- **Readability**: The pipe operator creates a clear data flow
- **Flexibility**: Easy to reorder arguments without changing semantics

**Comparison**

| Syntax | Example | Order Matters? |
|--------|---------|----------------|
| Positional | `foo(12, 7)` | Yes |
| Keyword args | `foo(first=12, second=7)` | No |
| Named tuple pipe | `(first=12, second=7) \|> foo` | No |

**Use Cases**

Named tuples with pipes are particularly useful when:
- You want to emphasize the data being passed
- Function calls have many parameters
- You want to make argument roles explicit
- You're building data transformation pipelines
- You prefer functional programming style with clear data flow
