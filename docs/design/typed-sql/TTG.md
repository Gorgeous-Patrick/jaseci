# TTG SQL AST integration

TTG uses the reusable `jaclang.sql` module for both specialized set-based queries
and layered BFS queries. The adapter lives in `jac/jaclang/runtime/ttg_sql.jac`;
the existing runtime retains traversal, caching, and topology ingestion.

The SQL module was ported from SQL branch commit `e61bf1a5e` to Jac 0.36.
Compatibility changes preserve the public typed API. PostgreSQL `BOOL_OR` was
added for frontier aggregation.

Verification:

- 140 SQL tests pass, including SQLite, PostgreSQL, and static checks.
- 13 topology/runtime tests pass.
- 145 full-row query comparisons against frozen SQL from `758366971` pass.
- 72 layered traversal comparisons pass across budgets, root inclusion,
  direction patterns, and actual undirected edges.

The frozen SQL oracle is `jac/tests/runtimelib/fixtures/ttg_sql_legacy.jac`.
Run `jac test jac/tests/runtimelib/test_topology_index.jac -v` to repeat the
runtime comparisons with the branch's configured PostgreSQL distribution.
These comparisons establish result equivalence; they do not measure performance.
