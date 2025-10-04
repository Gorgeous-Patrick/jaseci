The `global` and `nonlocal` statements control variable scope, allowing functions to modify variables from outer scopes rather than creating local shadows.

**Global Statement**

Line 7 shows `global x` which declares that `x` refers to the module-level global variable defined on line 3. Without this statement, line 9's assignment `x = 'Jaclang is '` would create a new local variable instead of modifying the global.

**Nonlocal Statement**

Line 15 shows `nonlocal y` which declares that `y` refers to the enclosing function's variable (line 10 in `outer_func`), not a global or new local. Line 17's assignment modifies the outer function's `y` variable.

**Scope Resolution**

Without `global` or `nonlocal`, assignments create new local variables. These keywords alter this behavior:
- `global`: Access module-level variables
- `nonlocal`: Access enclosing function's variables (but not global scope)

**Multiple Names**

Line 32 shows declaring multiple global variables: `global a, b, c`. Line 46 shows declaring multiple nonlocal variables: `nonlocal var1, var2, var3`. This is more concise than separate statements for each variable.

**Nested Scope Example**

Lines 39-56 demonstrate nested scopes:
- `outer` scope defines `var1`, `var2`, `var3`
- `inner` function uses `nonlocal` to modify these outer variables
- Without `nonlocal`, `inner` would create new local variables
- With `nonlocal`, changes persist in the outer scope after `inner()` completes

**Global vs Nonlocal**

| Keyword | Accesses | Use Case |
|---------|----------|----------|
| `global` | Module-level variables | Modify module state from functions |
| `nonlocal` | Enclosing function variables | Closures, nested function state |

**Common Patterns**

Lines 5-23 show a typical pattern: outer function declares `global`, nested function declares `nonlocal`, creating three scope levels (global, outer, inner) with explicit control over which scope each variable belongs to.