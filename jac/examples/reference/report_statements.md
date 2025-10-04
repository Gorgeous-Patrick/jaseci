Report statements are a special feature of Jac's walker-based programming model, used to return data from walker executions back to the caller without terminating the walker's traversal.

**Basic Report Syntax**

Line 8 demonstrates the simplest report statement: `report "Processing started";`. The `report` keyword is followed by an expression whose value is returned to the caller. Unlike `return` statements which exit the function, `report` statements send data back while allowing the walker to continue executing.

**Reporting Different Expression Types**

The example shows reporting various types of values:
- **String literal** (line 8): `report "Processing started";` sends a simple string message
- **Arithmetic expression** (line 11): `report 42 * 2;` evaluates the expression and reports the result (84)
- **Variable value** (line 14): `report self.collected;` reports the value of an instance attribute
- **Complex expression** (line 17): `report {"status": "complete", "count": len(self.collected)};` reports a dictionary with computed values

**Report vs Return**

The key difference between `report` and `return`:

| Feature | `report` | `return` |
|---------|----------|----------|
| Terminates function | No | Yes |
| Can be called multiple times | Yes | No |
| Available in | Walkers (primarily) | All functions/methods |
| Use case | Send data during traversal | Exit and return value |

**Walker Context**

Report statements are primarily used in walker contexts (lines 3-19). As line 22 notes, reports are typically used in walker contexts. When a walker executes, each `report` statement sends a value back to the code that spawned the walker, allowing the walker to communicate results incrementally as it traverses the graph.

**Multiple Reports**

Lines 6-18 show a walker ability that contains multiple report statements. All of these will execute in sequence, each sending their respective values back to the caller. This allows a walker to report multiple pieces of information during a single traversal without stopping execution.

**Execution Semantics**

When `w spawn root;` executes on line 24:
1. The walker is created and begins traversal
2. Line 8's report sends `"Processing started"` to the caller
3. Line 11's report sends `84` to the caller
4. Line 14's report sends the `collected` list to the caller
5. Line 17's report sends the status dictionary to the caller
6. The walker continues or completes its traversal

The caller can collect all these reported values, though the specific mechanism for accessing them depends on the Jac runtime's API.

**Use Cases**

Report statements are particularly useful for:
- Streaming results from graph traversals
- Collecting data from multiple nodes during a walk
- Providing progress updates during long-running traversals
- Returning multiple related pieces of information from a single walker execution
- Implementing data collection or aggregation patterns across graph structures

**Distinction from Print**

While `print` outputs to the console, `report` sends structured data back to the calling code. Report values can be captured, processed, and used programmatically, making them suitable for building APIs and data processing pipelines with walkers.
