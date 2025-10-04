Import and include statements in Jac control module dependencies, allowing code to access functionality from other modules and packages.

**Basic Import**

Line 4 shows simple import: `import os;`. This imports the entire `os` module, making all its members accessible via `os.member_name`.

**Import with Alias**

Line 7 demonstrates aliasing: `import datetime as dt;`. The module is imported but referenced by the shorter name `dt` instead of `datetime`.

**Multiple Imports**

Line 10 shows importing multiple modules in one statement: `import sys, json, random;`. Comma-separated module names are all imported.

**Import From with Items**

Line 13 demonstrates selective imports: `import from math { sqrt as square_root, log, pi }`. This syntax:
- Imports specific items from a module (sqrt, log, pi)
- Can alias imported items (`sqrt as square_root`)
- Uses curly braces to group the imports

**Trailing Commas**

Line 16 shows that trailing commas are allowed in import lists: `import from collections { defaultdict, Counter, }`. This is useful for version control.

**Relative Imports** (commented)

Lines 19-24 show relative import syntax using dots:
- `.` - current package
- `..` - parent package
- `...` - grandparent package

The number of dots indicates how many levels up the package hierarchy to navigate.

**Usage**

Lines 28-34 demonstrate using imported items:
- `os.getcwd()` uses the os module
- `square_root(i + 1)` uses the aliased sqrt function
- `log(i + 1)` and `pi` use directly imported math members

**Import Patterns**

| Pattern | Syntax | Use Case |
|---------|--------|----------|
| Full module | `import module` | Need many items from module |
| Aliased module | `import module as alias` | Shorter names, avoid conflicts |
| Selective | `import from module { items }` | Only need specific items |
| Aliased items | `import from module { item as alias }` | Rename to avoid conflicts |
| Relative | `import from . { module }` | Package-relative imports |