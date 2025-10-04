Jac provides built-in support for unit testing through test blocks, allowing you to write tests directly in your source files alongside the code being tested.

**Test Block Syntax**

Lines 4-6, 9-11, and 14-16 demonstrate the test block syntax. The general form is:

`test test_name { assertions and test code }`

Where:
- `test` is the keyword that begins a test block
- `test_name` is the identifier for the test
- The curly braces contain the test code, typically including assertions

**Test Blocks**

Line 4-6 defines `test1`, which uses `assert almostEqual(4.99999, 4.99999);` to check if two floating-point numbers are approximately equal. The `almostEqual` function is useful for comparing floating-point values where exact equality might fail due to precision issues.

Line 9-11 defines `test2`, which uses a simple equality assertion: `assert 5 == 5;`. This verifies that the integer 5 equals itself.

Line 14-16 defines `test3`, which uses a membership assertion: `assert "e" in "qwerty";`. This verifies that the character "e" exists in the string "qwerty".

**Assertion Semantics**

The `assert` statement checks if a condition is true:
- If the condition is true, execution continues normally
- If the condition is false, an AssertionError is raised and the test fails

Assertions are the primary mechanism for verifying expected behavior in tests. Each test can contain multiple assertions.

**Running Tests**

Lines 18-26 show how to execute tests programmatically using the `jac test` command. Line 18 uses `with entry:__main__` to ensure this code only runs when the file is executed directly (not when imported).

Lines 21-24 use Python's `subprocess.run` to execute the Jac test runner:
- `["jac", "test", f"{__file__}"]` constructs the command to test the current file
- `stdout=subprocess.PIPE, stderr=subprocess.PIPE` capture the output
- `text=True` ensures output is returned as strings

Line 25 prints the test results from stderr, where test output is typically sent.

**Test Discovery and Execution**

When `jac test filename.jac` is run:
1. Jac scans the file for all `test` blocks
2. Each test block is executed in isolation
3. Assertions are evaluated
4. Results are reported (pass/fail for each test)
5. A summary is provided showing total tests run and any failures

**Test Naming**

Test names (like `test1`, `test2`, `test3`) should be descriptive. While these examples use simple names, production code typically uses names that describe what is being tested, such as `test_password_validation` or `test_user_creation`.

**Test Isolation**

Each test block runs independently. If one test fails, the others still execute. This ensures that a single failure doesn't prevent other tests from running.

**Use Cases**

Test blocks are useful for:
- Unit testing individual functions or methods
- Verifying object behavior
- Testing graph operations and walker logic
- Regression testing to ensure code changes don't break existing functionality
- Documentation through examples (tests serve as executable specifications)

**Best Practices**

Effective tests should:
- Be independent (not rely on other tests or execution order)
- Have descriptive names
- Test one specific behavior or scenario
- Include meaningful assertions
- Be fast to execute
- Cover both normal and edge cases
