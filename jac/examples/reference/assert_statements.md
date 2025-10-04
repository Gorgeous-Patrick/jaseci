Assert statements in Jac provide runtime validation and testing capabilities, allowing developers to verify assumptions about program state and create test cases.

**Basic Assert Syntax**

The assert statement has the form `assert <condition> , <optional_message>`. If the condition evaluates to false, an AssertionError is raised with the optional message.

Line 5 demonstrates a basic assert with a custom error message: `assert value > 0 , "Value must be positive"`. When `foo(-5)` is called on line 10, this assertion fails because `-5 > 0` is false.

**Exception Handling with Assertions**

Lines 9-13 show how to catch assertion failures using try-except blocks. The `except AssertionError as e` clause catches the raised exception, and the error message is accessible via the exception object `e`.

**Global Variables in Tests**

Line 16 defines global variables `a = 5` and `b = 2` using the `glob` keyword. These globals are accessible in subsequent test blocks, providing shared state for test cases.

**Test Blocks**

Jac provides a dedicated `test` keyword for defining test cases. Each test block has a name and contains assertions:

- **test1** (lines 19-21): Demonstrates `almostEqual(a, 6)`, which checks if `a` is approximately equal to 6 (within some tolerance). This test will fail since `a = 5`.

- **test2** (lines 23-25): Asserts `a != b`, verifying that 5 is not equal to 2. This test passes.

- **test3** (lines 27-29): Asserts `"d" in "abc"`, checking if the substring "d" appears in "abc". This test fails.

- **test4** (lines 31-33): Asserts `a - b == 3`, verifying that `5 - 2 == 3`. This test passes.

**Testing Semantics**

Test blocks serve as named units of testing that can be executed independently or as part of a test suite. Unlike regular functions:
- Tests are declarative and don't require explicit invocation
- They typically contain multiple assertions
- They integrate with testing frameworks that can discover and run them automatically
- Failed assertions within tests are reported with the test name for easy identification

**Assertion Functions**

The `almostEqual` function (line 20) is a specialized assertion helper for floating-point comparisons, allowing for small numerical differences due to precision limitations. This is essential when comparing computed float values where exact equality is not guaranteed.