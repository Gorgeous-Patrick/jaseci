# TTG SQL AST integration

TTG uses the reusable `jaclang.sql` module for both specialized set-based queries
and layered BFS queries. The adapter lives in `jac/jaclang/runtime/ttg_sql.jac`;
the existing runtime retains traversal, caching, and topology ingestion.

The SQL module was ported from SQL branch commit `be6b1e9ec` to Jac 0.36.
Compatibility changes preserve the public typed API. PostgreSQL `BOOL_OR` was
added for frontier aggregation.

Verification:

- 160 SQL tests pass, including SQLite, PostgreSQL, and static checks.
- 13 topology/runtime tests and three compiled-template reuse tests pass.
- 145 full-row query comparisons against frozen SQL from `758366971` pass.
- 72 layered traversal comparisons pass across budgets, root inclusion,
  direction patterns, and actual undirected edges.

The frozen SQL oracle is `jac/tests/runtimelib/fixtures/ttg_sql_legacy.jac`.
Run `jac test jac/tests/runtimelib/test_topology_index.jac -v` to repeat the
runtime comparisons with the branch's configured PostgreSQL distribution.
The adapter caches up to 128 compiled SQL templates per path. Request-specific
IDs, budgets and depth are bound without reconstructing the AST. Structural flags
and canonical specification contents identify distinct templates. The cached
values contain SQL, fixed constants and parameter metadata; no AST is retained.

See [performance measurements](../../../benchmarks/ttg-sql/README.md) for raw
samples, first-call compilation, warm binding and database-call timing.
