Try statements provide structured exception handling, allowing you to catch and handle errors gracefully instead of letting them crash your program.

**Basic Try-Except Structure**

Lines 5-9 demonstrate the fundamental try-except syntax. The `try` block (lines 5-6) contains code that might raise an exception. If an exception occurs, execution jumps to the matching `except` block (lines 7-9). Line 7 shows `except Exception as e`, which catches any exception of type `Exception` (or its subclasses) and binds it to the variable `e` for use in the handler.

In this example, line 6 attempts division by zero, which raises a `ZeroDivisionError`. Since `ZeroDivisionError` is a subclass of `Exception`, it's caught and line 8 prints the exception object.

**Multiple Except Clauses**

Lines 12-20 demonstrate handling different exception types with multiple except clauses. The try block (lines 12-13) attempts to convert a string to an integer, which raises a `ValueError`.

The except clauses are evaluated in order:
- Line 14 catches `ValueError` and binds it to `ve`
- Line 16 catches `TypeError` and binds it to `te`
- Line 18 catches any other `Exception` and binds it to `e`

When an exception is raised, Jac checks each except clause in order and executes the first one that matches the exception type. In this case, since `int("not a number")` raises `ValueError`, line 14's handler matches and executes line 15.

**Try-Except-Else**

Lines 23-29 demonstrate the `else` clause, which executes only if no exception was raised in the try block. Line 24 performs division that succeeds, so no exception occurs. Because the try block completes successfully, the else block (lines 27-28) executes and prints the result.

The else clause is useful for:
- Code that should only run if the try block succeeded
- Distinguishing between setup (try) and success handling (else)
- Keeping exception-prone code in the try block while putting other code in else

**Try-Finally**

Lines 32-39 demonstrate the `finally` clause, which always executes regardless of whether an exception occurred. The finally block (lines 37-38) runs after the try block and any except handlers, even if an exception occurred or was handled.

Finally clauses are essential for:
- Cleanup operations (closing files, releasing resources)
- Ensuring critical code runs no matter what
- Logging or auditing that must happen regardless of errors

In this example, line 38 always prints, whether or not a file operation would have succeeded.

**Complete Try-Except-Else-Finally**

Lines 42-51 show all four clauses together. The execution order is:
1. Try block (lines 42-44) attempts the operation
2. If exception: matching except block (lines 45-46)
3. If no exception: else block (lines 47-48)
4. Always: finally block (lines 49-50)

In this example, no exception occurs (valid list access), so line 44 prints the value, then line 48 in the else block executes, and finally line 50 in the finally block executes.

**Exception Binding**

The `as variable` syntax (lines 7, 14, 16, 18, 45) binds the exception object to a variable that can be used in the handler. This variable is only available within the except block's scope. If you don't need to examine the exception, you can omit the `as` clause: `except ValueError { ... }`.

**Exception Hierarchy**

When using multiple except clauses, order matters because Python checks them sequentially and uses the first match:
- More specific exceptions should come before general ones
- `Exception` catches most exceptions, so it should be last
- Specific exceptions like `ValueError`, `TypeError` should come first

**Bare Except (Currently Unsupported)**

Lines 53-58 show a commented-out bare except clause that catches any exception without specifying a type. The TODO comment indicates this feature is not yet fully supported in Jac.

**Best Practices**

The examples demonstrate several exception handling best practices:
- Catch specific exceptions rather than using broad catches
- Use else for code that should only run on success
- Use finally for cleanup that must always occur
- Combine all clauses when you need complete error handling
- Bind exceptions to variables when you need to examine them
