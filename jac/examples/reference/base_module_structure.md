Jac modules support docstrings and entry points that provide structure and documentation at the module level.

**Module Docstrings**

Lines 3-8 demonstrate a module-level docstring. This is a string literal that appears at the very beginning of a module, before any code elements. It serves as documentation for the entire module and can be accessed programmatically for generating documentation or providing help text.

The docstring explains: "If there is only one docstring before the first element, it is assumed to be a module docstring." This means the position of the docstring determines its scope - a docstring at the module's start documents the module itself.

**Function Docstrings**

Lines 10-13 show a function with a docstring: `"""A docstring for add function"""` appears immediately before the `add` function definition. This documents the specific function rather than the module.

Docstrings can be attached to any module element (functions, classes, methods, etc.) by placing a string literal immediately before the element definition.

**Functions Without Docstrings**

Lines 16-18 show a function without a docstring. The `subtract` function is perfectly valid without documentation, though best practices encourage documenting all public APIs.

**Entry Points**

Lines 21-23 demonstrate a named entry point using `with entry:__main__`. This syntax creates a conditional entry point that executes only when the module is run as the main program (not when imported).

The `:__main__` label specifies this is the main entry point. When the module is executed directly, this block runs and calls `print(add(1, subtract(3, 1)))`, which:
1. Calls `subtract(3, 1)` → returns `2`
2. Calls `add(1, 2)` → returns `3`
3. Prints `3`

**Entry Point Semantics**

Entry points marked with `:__main__` follow the common pattern from Python and other languages where code only executes when the file is the entry point of the program. This allows modules to contain both reusable library code (the functions) and executable scripts (the entry block) in the same file.