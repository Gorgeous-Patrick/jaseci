Atomic expressions in Jac feature the atomic forward pipe operator `:>`, which enables clean, left-to-right function composition by passing values directly to functions.

**Atomic Forward Pipe Operator**

The `:>` operator takes the value on its left and passes it as an argument to the function on its right. This creates a more readable flow when chaining operations.

Line 5 demonstrates the basic usage: `"Hello world!" :> print`. This is equivalent to `print("Hello world!")`, but the pipe syntax emphasizes the data flow from left to right.

**Chained Atomic Pipes**

Line 8 shows multiple pipes chained together: `"Welcome" :> type :> print`. This expression:
1. Takes the string `"Welcome"`
2. Passes it to `type()`, which returns the string's type object
3. Passes that type object to `print()`

The left-to-right flow makes the sequence of transformations easier to read than nested function calls like `print(type("Welcome"))`.

**Atomic Pipes with Lambdas**

Lines 11-12 demonstrate using atomic pipes with lambda expressions:
`result = 5 :> (lambda x: int : x * 2) :> (lambda x: int : x + 10)`

This chains operations:
1. Start with value `5`
2. Pass to first lambda which doubles it: `5 * 2 = 10`
3. Pass result to second lambda which adds 10: `10 + 10 = 20`

The atomic pipe operator is particularly useful for creating data transformation pipelines where the flow of data is more important than the traditional function call syntax. It's called "atomic" because it passes the entire value as a single unit to the next function in the chain.