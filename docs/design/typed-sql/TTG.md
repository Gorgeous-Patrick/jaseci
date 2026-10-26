# TTG SQL construction

TTG uses `jaclang.sql` for specialized set-based and layered BFS queries. The
adapter is `jac/jaclang/runtime/ttg_sql.jac`. Its public compilation and runtime
traversal interfaces are unchanged.

The SQL module is synchronized from SQL branch commit `aab98c5ab`. It uses static
expression signatures, lightweight structural CTE planning, parameterized rendering,
and named runtime slots. Whole-query semantic analysis is an explicit diagnostic
operation. The Jac 0.36 port removes impl-header type parameters, parenthesizes
comprehension operands, renames locals shadowing SQL functions, and places the
`field` declaration after object definitions to avoid generated-field collisions.

## Constructor-local field information

Each uncached builder creates one `_BuildColumns` local variable and passes it to
its helper functions. It derives each source's schema through one local schema
dictionary, indexes field definitions by name, and constructs typed column
references from those definitions. Repeated access to the same source and column
reuses that expression. Separate source bindings keep distinct expressions.

The context retains source identities until the build completes. Schema summaries,
field dictionaries, and expressions belong to that build; they are not attached to
AST objects, global caches, or the compiled result. A later build creates a fresh
context. The builders keep their graph stable during construction; forward CTE
bindings use their declared output fields.

Each specialized/layered path also has a process-local LRU cache of at most 128
compiled templates. Origin/frontier/seen IDs, limits and depth are runtime bindings.
Template keys snapshot specifications and structural flags. Compiled templates
contain SQL, fixed parameters and slot metadata, with no AST or build context.

## Verification

- 176 SQL tests cover SQLite, PostgreSQL, static signatures and builder contracts.
- Six TTG tests cover template reuse, context isolation and source binding identity.
- 13 topology/runtime tests pass, including 145 full-row comparisons against the
  frozen string generator and 72 complete layered traversal comparisons.

The frozen oracle is `jac/tests/runtimelib/fixtures/ttg_sql_legacy.jac`.

```sh
jac test jac/tests/runtimelib/test_ttg_sql_bind.jac -v
jac test jac/tests/runtimelib/test_topology_index.jac -v
```

Performance measurements and temporary harnesses are maintained separately.
