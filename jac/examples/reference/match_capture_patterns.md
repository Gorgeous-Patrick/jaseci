Capture patterns in Jac's match statements allow you to bind values to variables during pattern matching. The most common capture pattern is the wildcard pattern `_`, which matches any value without binding it.

**Wildcard Pattern**

Line 8 demonstrates the wildcard capture pattern using `case _:`. The underscore `_` is a special pattern that matches any value, serving as a catch-all case when no other patterns match. In this example, since `day` contains `" sunday"` (with a leading space), it doesn't match the literal string `"monday"` on line 6, so execution falls through to the wildcard pattern on line 8, which prints `"other"`.

The wildcard pattern is typically used as the last case in a match statement to handle all unmatched values, similar to a `default` case in switch statements from other languages. It ensures that the match statement always has a case that executes, preventing the match from silently doing nothing.

**Capture Semantics**

Unlike named capture patterns that bind matched values to variables, the wildcard `_` discards the matched value without creating any binding. This is useful when you want to match any remaining cases but don't need to use the actual value in the case body.
