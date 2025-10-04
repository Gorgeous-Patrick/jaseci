Context managers in Jac provide automatic resource management using the `with` statement, ensuring proper setup and cleanup of resources even when errors occur.

**Basic With Statement**

Line 5 demonstrates the basic `with` statement: `with open(__file__, 'r') as file {}`. This:
- Calls `open()` to acquire the file resource
- Binds the result to the variable `file`
- Automatically closes the file when the block ends (even if an exception occurs)

The `as` clause binds the context manager's `__enter__` return value to a variable for use within the block.

**With Without Binding**

Lines 8-10 (commented) show that `as` is optional: `with some_context_manager() { ... }`. This is useful when you need the setup/cleanup behavior but don't need to reference the resource.

**Multiple Context Managers**

Lines 13-16 (commented) demonstrate managing multiple resources: `with open("file1.txt") as f1, open("file2.txt") as f2 { ... }`. Multiple managers are separated by commas, and all are properly cleaned up in reverse order of acquisition.

**Async Context Managers**

Lines 19-21 (commented) show async context management: `async with async_context_manager() as resource { ... }`. This works with asynchronous resources that implement `__aenter__` and `__aexit__` methods.

**Implementing Context Managers**

Lines 24-38 demonstrate creating a custom context manager class:

**__enter__ Method** (lines 25-28):
- Called when entering the `with` block
- Performs resource acquisition or setup
- Returns the resource object (often `self`)
- The return value becomes the `as` variable binding

**__exit__ Method** (lines 30-37):
- Called when exiting the `with` block (success or exception)
- Receives exception information if an error occurred:
  - `exc_type`: Exception class (or None)
  - `exc_val`: Exception instance (or None)
  - `exc_tb`: Traceback object (or None)
- Performs cleanup (closing files, releasing locks, etc.)
- Can suppress exceptions by returning True (though this example returns None)

**Using Custom Context Managers**

Lines 40-42 use the custom Resource class: `with Resource() as r { print("Using resource"); }`. This prints:
1. "Acquiring resource" (from `__enter__`)
2. "Using resource" (from the block body)
3. "Releasing resource" (from `__exit__`)

**Nested Context Managers**

Lines 45-49 (commented) show nested `with` statements, which can also be written using the comma syntax. Nested managers are cleaned up in reverse order (inner to outer).

**Exception Safety**

The key benefit of context managers is exception safety: cleanup code in `__exit__` runs even if the block raises an exception. This prevents resource leaks and ensures consistent state management.

Common use cases include file I/O, database connections, locks, network sockets, and any resource requiring paired acquire/release operations.