Singleton patterns match against special constant values that have unique identities in the language: `True`, `False`, and `None`.

**Singleton Pattern Matching**

Lines 8 and 10 demonstrate singleton patterns. Line 8 uses `case True:` to match the boolean singleton `True`, and line 10 uses `case None:` to match the `None` singleton. These patterns check for identity (using the `is` operator semantics) rather than equality.

**Identity vs Equality**

Singleton patterns are special because they match based on identity, not just value equality. While `True == 1` evaluates to `True` in Python-like languages, the singleton pattern `case True:` will only match the actual `True` boolean value, not the integer `1`. This ensures type-safe matching.

**The Three Singletons**

Jac recognizes three singleton values that can be used in singleton patterns:
- `True`: The boolean true value
- `False`: The boolean false value
- `None`: The null/nothing value

**Example Behavior**

In this example, line 5 matches against `True` (not the variable `data` which is also `True`). Since the match expression evaluates to `True`, the pattern on line 8 matches and line 9 executes, printing `"Matched the singleton True."`. If the match expression were `None`, line 10's pattern would match instead, executing line 11.

**Common Use Cases**

Singleton patterns are commonly used for:
- Checking if optional values are `None`
- Handling boolean flags in configuration or state machines
- Distinguishing between boolean values and other truthy/falsy values
