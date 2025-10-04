Pipe expressions use the `|>` operator to pass values into functions from left to right, creating a natural data flow syntax.

**Basic Forward Pipe Syntax**

Lines 17-19 demonstrate the basic forward pipe operator. Line 18 shows `result = number |> square`, which is equivalent to `result = square(number)`. The `|>` operator takes the value on its left side (`number`, which is 5) and passes it as an argument to the function on its right side (`square`).

The forward pipe operator creates a left-to-right reading flow that emphasizes data transformation: "number flows into square". This can be more intuitive than traditional function call syntax, especially when chaining multiple transformations.

**Function Definitions**

Lines 3-13 define three transformation functions:
- `square` (line 3): raises input to the power of 2
- `double` (line 7): multiplies input by 2
- `increment` (line 11): adds 1 to input

These functions demonstrate how pipe works with different operations.

**Chained Forward Pipes (Currently Limited)**

Lines 21-24 show a commented-out example of chained forward pipe operations. The intended syntax `value |> increment |> double |> square` would create a pipeline that evaluates from left to right:
1. `value` (3) is piped to `increment`, producing 4
2. 4 is piped to `double`, producing 8
3. 8 is piped to `square`, producing 64

However, the TODO comment indicates this feature is not yet fully working. When complete, this will enable elegant function composition in a left-to-right data flow style.

**Pipe with Built-in Functions**

Lines 27-29 demonstrate using pipe with built-in functions. Line 28 shows `total = data |> sum`, which passes the list `[1, 2, 3, 4, 5]` to the `sum` function, producing 15. The pipe operator works with any callable, including built-in functions, not just user-defined functions.

**Pipe to Lambda Expressions**

Lines 31-33 demonstrate piping to lambda expressions. Line 32 shows `x = 10 |> (lambda n: int : n * 3)`, which pipes the value 10 into an inline lambda function that multiplies by 3, resulting in 30.

The lambda must be wrapped in parentheses when used with the pipe operator. This pattern is useful for one-off transformations without defining a separate function, while maintaining the left-to-right data flow style.

**Comparison to Pipe Back**

The forward pipe operator `|>` is the reverse of the pipe back operator `<|` (covered in pipe_back_expressions.md):
- Forward pipe: `value |> function` (left to right, data-first)
- Pipe back: `function <| value` (right to left, function-first)

**Use Cases**

Forward pipe is particularly useful when:
- You want to emphasize data flow and transformation
- You're building a pipeline of operations
- You prefer left-to-right reading order
- You're transforming data through multiple steps
- You're familiar with pipe operators from functional languages (F#, Elixir) or Unix shells

**Advantages**

The pipe operator offers several benefits:
- Improved readability for data transformation sequences
- Eliminates deeply nested function calls
- Makes the order of operations explicit
- Reduces the need for intermediate variables
