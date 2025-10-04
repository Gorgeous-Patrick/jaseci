Code blocks in Jac are sequences of statements enclosed in curly braces `{}`. They provide structure for organizing code within functions, control flow constructs, and entry points.

**Code Block Structure**

Lines 3-20 show an entry code block that contains multiple statements. Code blocks use curly brace syntax `{ ... }` and can contain any valid statements.

**Expression Statements**

Line 5 demonstrates an expression statement: `print("Welcome to the world of Jaseci!");`. Any expression followed by a semicolon becomes a statement. The expression is evaluated for its side effects (in this case, printing output).

**Nested Definitions**

Lines 8-10 show that function definitions can appear inside code blocks. The `add` function is defined within the entry block's scope:

`def add(x: int, y: int) -> int { return (x + y); }`

Functions defined inside blocks have local scope relative to that block.

**Function Calls as Statements**

Line 13 shows a function call as an expression statement: `print(add(10, 89));`. The function is called, its result is passed to `print`, and the expression completes.

**Statement Types**

Lines 16-19 demonstrate that code blocks can contain different statement types:

- **Assignment statement** (line 16): `x = 42;` binds a value to a variable
- **Control flow statement** (lines 17-19): `if x > 0 { print("Positive"); }` contains a nested code block

**Semicolons**

Jac requires semicolons to terminate most statements. This explicit termination allows the parser to distinguish between statement boundaries and enables more flexible formatting.

**Nested Code Blocks**

The if statement on lines 17-19 contains its own code block. Code blocks can be nested arbitrarily deep, with each level creating a new scope for local variables (though the specifics of scoping rules depend on the statement type).

Code blocks are the fundamental organizational unit in Jac, grouping related statements and defining scope boundaries for variables and functions.