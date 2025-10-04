Lambda expressions in Jac create anonymous functions with concise syntax, supporting type annotations, default parameters, and inline logic.

**Lambda with Type Annotations**

Line 5 shows full lambda syntax: `lambda a: int, b: int -> int : b + a`. Format breakdown:
- `lambda` keyword
- Parameters with types: `a: int, b: int`
- Return type annotation: `-> int`
- Colon separator: `:`
- Expression body: `b + a`

**Parameterless Lambda**

Lines 9-10 demonstrate lambda without parameters: `lambda : 5`. Simply returns the value 5 when called.

**Lambda Without Return Hint**

Lines 13-14 show lambda without return type: `lambda x: int, y: int : x + y`. Return type annotation is optional.

**Return Hint Without Parameters**

Lines 17-18 demonstrate return hint without params: `lambda -> int : 42`. Specifies return type but takes no arguments.

**Default Parameter Values**

Lines 21-24 show default parameters: `lambda x: int = 2, y: int = 3 : x * y`.
- Called with no args: uses defaults (2, 3) → 6
- Called with one arg: `multiply(5)` → 5 * 3 = 15
- Called with two args: `multiply(5, 10)` → 50

**Variadic Arguments**

Lines 27-28 note that lambdas don't support `*args` or `**kwargs` - use regular functions instead for variadic parameters.

**Lambda as Function Argument**

Lines 31-33 show passing lambda to `map`: `map(lambda x: int : x ** 2, numbers)`. This is a common functional programming pattern.

**Lambda with Filter**

Lines 36-37 demonstrate lambda in `filter`: `filter(lambda x: int : x % 2 == 0, numbers)`. Returns only even numbers.

**Complex Lambda**

Lines 40-41 show lambda with conditional: `lambda a: int, b: int : a if a > b else b`. The lambda body can be any single expression, including ternaries.

**Lambda Limitations**

Lambdas are restricted to single expressions - they cannot contain:
- Multiple statements
- Assignments (except walrus :=)
- Control flow statements (if/for/while as statements)

For complex logic, use regular `def` functions instead.