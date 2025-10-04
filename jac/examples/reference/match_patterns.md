This example provides a comprehensive overview of all the different pattern types available in Jac's match statements. The function `match_example` (lines 8-53) demonstrates each pattern type with detailed comments.

**MatchValue Pattern**

Lines 11-12 show the value pattern, which matches against a specific literal value. The pattern `case 42:` matches when the input data equals exactly `42`. This is the simplest form of pattern matching.

**MatchSingleton Pattern**

Lines 15-18 demonstrate singleton patterns for matching special constant values. `case True:` matches the boolean singleton `True`, and `case None:` matches the `None` singleton. These patterns are used for matching these specific built-in constant values.

**MatchSequence Pattern**

Lines 21-22 show sequence pattern matching with `case [1, 2, 3]:`. This pattern matches a list (or other sequence) that contains exactly three elements with values `1`, `2`, and `3` in that order. The sequence must match both the length and the values exactly.

**MatchStar Pattern**

Lines 25-28 demonstrate the star pattern `case [1, *rest, 3]:`, which matches sequences that start with `1` and end with `3`, capturing all middle elements in the variable `rest`. The `*rest` syntax is similar to unpacking and allows matching sequences of variable length. If the sequence is `[1, 2, 2, 3]`, then `rest` would be `[2, 2]`.

**MatchMapping Pattern**

Lines 31-34 show mapping (dictionary) pattern matching with `case {"key1" : 1, "key2" : 2, **rest}:`. This matches dictionaries that contain at least the specified keys with their values, capturing any additional key-value pairs in the `rest` variable using the `**rest` syntax.

**MatchClass Pattern**

Lines 37-38 demonstrate class pattern matching with `case Point(int(a), y = 0):`. This pattern checks if the data is an instance of `Point`, matches the first positional attribute (converting it to int and binding to `a`), and checks that the `y` attribute equals `0`. This combines type checking, attribute extraction, and value matching.

**MatchAs Pattern**

Lines 41-44 show the "as" pattern `case [1, 2, rest_val as value]:`, which matches a sequence of three elements starting with `1` and `2`, while binding the third element to the variable `value`. The `as` syntax allows you to capture a matched value or sub-pattern into a variable for use in the case body.

**MatchOr Pattern**

Lines 47-48 demonstrate the or pattern `case [1, 2] | [3, 4]:`, which matches if the data matches either the left pattern `[1, 2]` or the right pattern `[3, 4]`. The `|` operator allows combining multiple patterns, succeeding if any one of them matches.

**Wildcard Pattern**

Line 50 shows the wildcard pattern `case _:`, which matches any value and serves as a catch-all default case. This ensures that if none of the previous patterns match, there's still a case to handle the input.

**Pattern Composition**

These pattern types can be combined and nested to create complex matching logic. For example, you could have a class pattern containing sequence patterns, or a mapping pattern with or patterns for values. The example on line 56 demonstrates calling this function with a `Point` object, which would match the MatchClass pattern on line 37.
