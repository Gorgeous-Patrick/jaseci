Raise statements are used to explicitly throw exceptions, signaling error conditions or exceptional situations that need to be handled by calling code.

**Basic Raise Statement**

Lines 4-6 demonstrate the basic raise syntax. Line 5 shows `raise ValueError("Value must be non-negative")`, which creates a `ValueError` exception with a descriptive message and immediately throws it. This interrupts normal program flow and begins searching for an exception handler. Lines 40-44 show this exception being caught and handled.

**Exception Chaining with raise...from**

Lines 9-16 demonstrate exception chaining using the `raise ... from` syntax. Line 14 shows `raise RuntimeError("Division failed") from e`, which raises a new exception while preserving the original exception as the cause. This creates a chain of exceptions that provides context about the error's origin.

Exception chaining is useful when you want to:
- Wrap low-level exceptions with higher-level, more meaningful ones
- Provide additional context about what operation was being attempted
- Maintain the full exception history for debugging

The chained exception can be accessed via the `__cause__` attribute (as noted in the commented line 51), allowing error handlers to examine the entire exception chain.

**Bare Raise (Re-raising)**

Lines 18-26 demonstrate the bare raise statement. Line 24 shows simply `raise;` without any arguments, which re-raises the currently active exception. This is only valid within an exception handler (an `except` clause).

Bare raise is useful when you want to:
- Log or inspect an exception before propagating it
- Perform cleanup actions before letting the exception continue
- Conditionally handle some exceptions while re-raising others
- Preserve the original exception's traceback information

In this example, line 22 prints a message when the exception is caught, then line 24 re-raises the same exception to propagate it to the outer handler (lines 55-59).

**Conditional Raise**

Lines 28-36 demonstrate using raise statements for input validation. Lines 29-30 show raising a `ValueError` when the input is `None`, and lines 32-34 show raising a `TypeError` when the input is not an integer. This pattern is common for validating function arguments and enforcing preconditions.

The error messages (lines 30 and 33) include specific information about what went wrong, making debugging easier. Line 33 uses an f-string to include the actual type received in the error message.

**Exception Types**

The example uses several standard exception types:

| Exception Type | Use Case | Example (Line) |
|----------------|----------|----------------|
| `ValueError` | Invalid value for expected type | Line 5, 20, 30 |
| `ZeroDivisionError` | Division by zero | Line 12 (caught) |
| `RuntimeError` | General runtime error | Line 14 |
| `TypeError` | Wrong type for operation | Line 33 |

**Exception Handling Flow**

When an exception is raised:
1. Normal execution stops at the raise statement
2. The runtime searches for an appropriate exception handler (except clause)
3. If found, the handler executes and can access the exception object
4. If not found, the exception propagates up the call stack
5. If no handler catches it, the program terminates with an error

**Best Practices**

The examples demonstrate several best practices:
- Provide descriptive error messages (all raise statements include messages)
- Use specific exception types (ValueError, TypeError, etc.) rather than generic Exception
- Chain exceptions to preserve error context (line 14)
- Validate inputs early and fail fast (lines 29-34)
