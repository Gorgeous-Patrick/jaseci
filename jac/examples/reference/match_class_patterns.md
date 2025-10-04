Class patterns enable matching against instances of specific types and extracting their attributes in a single operation. This is one of the most powerful pattern matching features in Jac.

**Class Pattern Structure**

Line 11 demonstrates a class pattern: `case Point(int(a), y = 0):`. This pattern matches objects of type `Point` and simultaneously checks and extracts attribute values. The pattern has two components:

1. **Positional matching**: `int(a)` attempts to match the first positional attribute (in this case `x` from line 4) by converting it to an integer and binding the result to variable `a`
2. **Keyword matching**: `y = 0` matches only when the `y` attribute equals `0`

**Type Checking and Conversion**

The `int(a)` portion performs both type checking and conversion. First, it checks if the `x` attribute can be converted to an integer. If successful, the converted value is bound to the variable `a`. In this example, `Point(x=9, y=0)` has `x=9` which successfully converts to integer `9`, and `y=0` matches exactly, so the pattern succeeds and line 12 executes, printing `"Point with x=9 and y=0"`.

**Attribute Matching**

The `y = 0` keyword argument specifies that the pattern only matches when the object's `y` attribute equals `0`. This allows you to match specific object states. If `y` had any other value, the pattern would fail and execution would fall through to the wildcard pattern on line 13.

**Usage**

Class patterns are particularly useful for destructuring objects and handling different object states in a clean, declarative way. They combine instance checking, attribute extraction, and conditional matching into a single expressive pattern.
