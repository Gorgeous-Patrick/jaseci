Inline Python allows embedding native Python code within Jac modules using the `::py::` delimiter syntax, enabling interoperability between Jac and Python.

**Jac Code Block**

Lines 3-5 show standard Jac code: a `with entry` block that prints "hello ".

**Python Code Block Delimiters**

Lines 8-13 demonstrate the Python code block syntax:
- Opening delimiter: `::py::`
- Python code (lines 9-12)
- Closing delimiter: `::py::`

**Python Code Execution**

Lines 9-12 contain native Python code:
- Line 9: `def foo():` - Python function definition
- Line 10: `print("world")` - Python print statement
- Line 12: `foo()` - Call the Python function

This code executes as if written in a pure Python file.

**Interoperability**

The Python code block:
- Has access to Python's standard library and syntax
- Can define functions, classes, and variables
- Can be called from Jac code (and vice versa, depending on implementation)
- Executes in the same runtime environment as Jac code

**Use Cases**

Inline Python is useful for:
- Leveraging existing Python libraries
- Using Python-specific features not yet in Jac
- Gradual migration from Python to Jac
- Performance-critical sections that benefit from Python optimizations
- Integration with Python ecosystems

The `::py::` syntax provides clear visual separation between Jac and Python code, making it easy to identify language boundaries in mixed-language files.