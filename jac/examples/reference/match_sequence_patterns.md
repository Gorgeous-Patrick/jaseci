Sequence patterns enable matching against ordered collections like lists and tuples, checking both the structure and contents of the sequence.

**Basic Sequence Pattern**

Line 6 demonstrates a sequence pattern `case [1, 2, 3]:` that matches a list containing exactly three elements with the values `1`, `2`, and `3` in that exact order. The pattern performs both length checking and element-wise value comparison.

**Exact Matching Requirements**

For a sequence pattern to match, several conditions must be met:
1. The matched value must be a sequence type (list, tuple, etc.)
2. The sequence must have exactly the same length as the pattern (3 elements in this case)
3. Each element must match its corresponding position in the pattern (first element must be `1`, second must be `2`, third must be `3`)

In this example, `data` is set to `[1, 2, 3]` on line 4, which exactly matches the pattern on line 6, so line 7 executes and prints `"Matched"`.

**Pattern Failure**

The pattern would fail to match if:
- The value is not a sequence (e.g., a number, string, or dictionary)
- The sequence has a different length (e.g., `[1, 2]` or `[1, 2, 3, 4]`)
- Any element has a different value (e.g., `[1, 2, 4]`)

If the pattern fails, execution falls through to the wildcard pattern on line 8, which would print `"Not Found"`.

**Sequence Types**

Sequence patterns work with various sequence types including lists, tuples, and other ordered collections. The pattern `[1, 2, 3]` would match both `[1, 2, 3]` (a list) and `(1, 2, 3)` (a tuple) since both are sequences with the same elements in the same order.
