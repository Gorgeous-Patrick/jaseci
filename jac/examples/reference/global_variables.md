Global variables in Jac are module-level declarations that can have access control tags specifying visibility and mutability.

**Let with Access Tags**

Line 4 shows `let:priv a = 5` - a private module-level variable using `let`. The `:priv` tag restricts access to the current module.

**Global with Access Tags**

Lines 7, 10, 13 demonstrate `glob` declarations with different access levels:
- Line 7: `glob:pub X = 10` - public, accessible from other modules
- Line 10: `glob:protect y = 15` - protected access
- Line 13: `glob z = 20` - no access tag, uses default visibility

**Access Tag Semantics**

| Access Tag | Visibility | Example |
|------------|------------|---------|
| `:priv` | Private to module | Line 4 |
| `:pub` | Public, exportable | Line 7 |
| `:protect` | Protected access | Line 10 |
| (none) | Default visibility | Line 13 |

**Object Declarations with Access**

Line 16 shows `obj:priv Myobj{}` - a private object definition. Access tags apply to any module-level declaration, not just variables.

**Entry Point**

Line 18 shows `with entry:__main__` - conditional execution only when the module is run directly (not imported). Line 19 accesses all the declared globals.

**Global vs Let**

Both `glob` and `let` create module-level variables:
- `glob` explicitly declares global scope
- `let` can also be used at module level with similar semantics
- Both support access tags
- Choice between them is often stylistic, though `glob` more clearly indicates module-wide scope

Access tags enable encapsulation and API control at the module level, allowing developers to specify which elements are part of the public interface versus internal implementation details.