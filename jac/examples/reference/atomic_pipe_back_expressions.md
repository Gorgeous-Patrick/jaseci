Atomic pipe back expressions use the `<:` operator to create right-to-left data flow, providing an alternative to the forward pipe that can be more natural in certain contexts.

**Atomic Backward Pipe Operator**

The `<:` operator takes the value on its right and passes it as an argument to the function on its left. This is the reverse of the forward pipe `:>`.

Line 5 demonstrates basic usage: `print <: "Hello world!"`. This is equivalent to `print("Hello world!")`, but reads right-to-left. The data source is on the right, flowing backward to the function on the left.

**Mixed Pipe Directions**

Line 12 shows a complex expression combining both pipe operators:
`c = len <: a + b :> len`

Breaking this down:
1. `a + b` concatenates the two lists
2. `:> len` pipes the concatenated list forward to `len()`, getting the length
3. `len <:` pipes that length value backward to another `len()` call

However, the second `len()` receives an integer (the first length), so this would actually cause an error. The example demonstrates syntax rather than correct semantics.

**Backward Pipe with Lambda**

Lines 16-17 show the backward pipe with a lambda expression:
`result = (lambda x:int : x * 3) <: 10`

This passes `10` backward to the lambda function, which multiplies it by 3, resulting in `30`. This is equivalent to `(lambda x:int : x * 3)(10)`.

**Choosing Pipe Direction**

The choice between forward `:>` and backward `<:` pipes is often stylistic:
- Forward pipes `value :> function` emphasize data flowing through transformations
- Backward pipes `function <: value` can feel more natural when the function is the focus

Both operators create the same function application but offer different ways to express the relationship between data and operations. The "atomic" designation indicates these operators work with complete values rather than partial application.