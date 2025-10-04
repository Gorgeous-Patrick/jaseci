Pipe back expressions use the `<|` operator to pass values into functions from right to left, providing an alternative to traditional function call syntax.

**Basic Pipe Back Syntax**

Lines 17-19 demonstrate the basic pipe back operator. Line 18 shows `result = double <| number`, which is equivalent to `result = double(number)`. The `<|` operator takes the value on its right side (`number`, which is 5) and passes it as an argument to the function on its left side (`double`).

The pipe back operator reverses the typical left-to-right reading order, making it read as "double, taking input from number" rather than "double of number". This can be more intuitive in certain contexts, particularly when emphasizing the data flow from source to transformation.

**Function Definitions**

Lines 3-13 define three simple transformation functions:
- `double` (line 3): multiplies input by 2
- `triple` (line 7): multiplies input by 3
- `negate` (line 11): returns negative of input

These functions are used to demonstrate how pipe back works with different functions.

**Chained Pipe Back (Currently Limited)**

Lines 21-24 show a commented-out example of chained pipe back operations. The intended syntax `negate <| triple <| double <| value` would evaluate from right to left:
1. `value` (2) is piped to `double`, producing 4
2. 4 is piped to `triple`, producing 12
3. 12 is piped to `negate`, producing -12

However, the TODO comment indicates this feature is not yet fully working. This would be analogous to function composition, creating a pipeline of transformations.

**Pipe Back with Lambda**

Lines 26-28 demonstrate using pipe back with lambda expressions. Line 27 shows `x = (lambda n:int : n * 3) <| 10`, which creates an inline lambda function and immediately applies it to the value 10. The lambda takes an integer `n` and returns `n * 3`, so the result is 30.

This pattern is useful when you need a one-off transformation without defining a separate function. The pipe back syntax makes it clear that 10 is the input being transformed.

**Pipe Back with Built-in Functions**

Lines 30-32 show using pipe back with built-in functions. Line 31 demonstrates `data = sum <| [1, 2, 3, 4, 5]`, which passes the list to the `sum` function, producing 15. This works with any callable, not just user-defined functions.

**Comparison to Forward Pipe**

The pipe back operator `<|` is the reverse of the forward pipe operator `|>` (covered in pipe_expressions.md):
- Forward pipe: `value |> function` (left to right, data-first)
- Pipe back: `function <| value` (right to left, function-first)

**Use Cases**

Pipe back is particularly useful when:
- You want to emphasize the transformation being applied
- The function name is more important than the data source
- You're composing functions in a right-to-left style
- You're familiar with operators like `<|` from functional languages (Haskell, F#, Elm)
