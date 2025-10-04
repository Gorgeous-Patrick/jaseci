Assignment statements in Jac provide multiple ways to bind values to variables, including simple assignment, type annotations, chained assignments, and augmented assignments.

**Basic Assignment**

Lines 5-6 demonstrate simple assignment using the `=` operator: `a = b = 16`. This is a chained assignment where both `a` and `b` receive the value 16. The assignment evaluates right-to-left, so 16 is first assigned to `b`, then that value is assigned to `a`.

**Let Assignment**

Lines 9-10 show the `let` keyword for assignment: `let c = 18`. The `let` keyword emphasizes the creation of a new binding. While functionally similar to regular assignment in many contexts, `let` can convey different semantics depending on scope and mutability requirements.

**Type Annotations**

Jac supports optional type annotations on assignments:

- Lines 13-14: `x: int = 42` declares `x` with type `int` and assigns it the value 42
- Lines 17-19: Type annotation without immediate assignment. `y: str` declares `y` as a string variable, which is then assigned "hello" on the next line

Type annotations serve as documentation and enable type checking, but don't enforce runtime type constraints unless explicitly checked.

**Augmented Assignment Operators**

Augmented assignments combine an operation with assignment. The general form is `var op= value`, which is equivalent to `var = var op value` but potentially more efficient.

| Operator | Operation | Example Line | Meaning |
|----------|-----------|--------------|---------|
| `+=` | Add and assign | 32 | `num = num + 5` |
| `-=` | Subtract and assign | 33 | `num = num - 3` |
| `*=` | Multiply and assign | 34 | `num = num * 2` |
| `/=` | Divide and assign | 35 | `num = num / 2` |
| `%=` | Modulo and assign | 36 | `num = num % 3` |
| `**=` | Exponentiate and assign | 37 | `num = num ** 2` |
| `//=` | Floor divide and assign | 28-29 | `c = c // 4` |
| `&=` | Bitwise AND and assign | 40 | `bits = bits & 7` |
| `|=` | Bitwise OR and assign | 41 | `bits = bits | 8` |
| `^=` | Bitwise XOR and assign | 42 | `bits = bits ^ 3` |
| `<<=` | Left shift and assign | 25-26 | `a = a << 2` |
| `>>=` | Right shift and assign | 22-23 | `a = a >> 2` |
| `@=` | Matrix multiply and assign | 45 (commented) | `matrix = matrix @ other` |

Lines 22-42 demonstrate most augmented operators. The sequence on lines 31-37 shows how augmented operators modify `num` through a series of arithmetic operations.

**Chained Assignments**

Line 56 demonstrates multiple chained assignments: `x = y = z = 100`. All three variables are assigned the value 100. This is equivalent to:
```
z = 100
y = 100
x = 100
```

**Assignment with Expressions**

Lines 60-61 show that the right-hand side of an assignment can be any expression: `result = 5 * (3 + 2)`. The expression is evaluated first (yielding 25), then assigned to `result`.

**Yield Expressions in Assignment**

Lines 48-53 mention that yield expressions can appear on the right side of assignments, though the example is commented out. This would allow capturing values from generator expressions.