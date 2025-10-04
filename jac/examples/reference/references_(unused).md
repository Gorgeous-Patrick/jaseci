This file documents the `&` (BW_AND) operator as a reference operator, which is defined in Jac's grammar but is currently unused or deprecated in the language.

**Grammar Definition**

Lines 9-10 explain that the reference operator is defined in the grammar rule for references: `ref rule: BW_AND? pipe_call` allows an optional `&` prefix before a pipe call expression. This means the grammar permits syntax like `&x` where `x` is a variable or expression.

**Current Status**

Line 13 clearly states that while the reference operator `&` is defined in the grammar, it is currently unused. This means:
- The parser recognizes the syntax
- The language specification includes it
- However, it may not have active runtime behavior
- It's either deprecated or reserved for future use

**Intended Semantics**

Based on the comment on line 4, the `&` operator was intended to create a reference to a variable. In languages with explicit reference semantics (like C++), this would create a reference that allows indirect access to a variable. The commented example on line 11 shows the hypothetical usage: `ref_x = &x;` would create a reference to variable `x`.

**Why It's Unused**

Jac, being a Python-influenced language, uses reference semantics by default for objects. In Python and similar languages:
- Variables already hold references to objects
- Assignment creates new references to the same object
- Explicit reference operators are typically unnecessary

The `&` operator may have been considered during language design but found to be redundant given Jac's object model.

**Practical Implications**

For current Jac programming:
- Do not use the `&` operator in production code
- It exists in the grammar for parsing purposes
- Future versions may remove it entirely or give it meaning
- Use standard variable assignment and object references instead

**Grammar Note**

The `BW_AND?` syntax in the grammar uses `?` to indicate the operator is optional. This means both `x` and `&x` would parse correctly as reference expressions, but only `x` (without the ampersand) has defined behavior in current Jac.

**Historical Context**

Many programming languages have evolved away from explicit reference operators:
- C uses `&` for addresses and `*` for dereference
- C++ uses `&` for references
- Python/JavaScript/Ruby use implicit references
- Jac appears to follow the implicit reference model

The presence of this unused operator in the grammar suggests Jac may have considered explicit reference semantics during design but ultimately adopted the simpler implicit reference model.
