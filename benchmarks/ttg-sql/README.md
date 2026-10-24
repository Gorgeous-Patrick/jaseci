# TTG SQL compilation and binding

Measured 2026-10-24 on Jac 0.36.1, CPython 3.14.6 and local PostgreSQL 18.6. The baseline is TTG `714e45988` before schema/analysis caching and binding. The current adapter ports SQL branch `be6b1e9ec` and caches compiled templates.

## Method

Six existing patterns, specialized and layered paths, two origins and budget/depth 12 on the overlap-budget fixture. Every new/legacy result is checked for exact equality. Build timing: first call recorded separately, then five total warmups and 50 measured calls. DB-call timing: five warmup pairs and 30 measured pairs in alternating order. SQL generation/binding and DB calls are timed separately. The raw files include all samples and one EXPLAIN ANALYZE BUFFERS JSON plan per version/case.

Baseline and current measurements are separate warm runs, so comparisons include run-to-run noise. Current warm times include canonicalizing specifications, cache lookup, parameter validation, dictionary construction and returning CompiledSQL. First-call times include template construction and compilation. DB-call times include driver processing, socket exchange, server work and decoding, and exclude SQL construction/binding.

## Median client construction/binding (ms)

| Pattern | Path | Previous AST rebuild | First current call | Warm current call |
|---|---|---:|---:|---:|
| 0 | specialized | 15.528 | 15.879 | 0.008279 |
| 1 | specialized | 15.515 | 11.204 | 0.006308 |
| 2 | specialized | 16.087 | 11.806 | 0.006308 |
| 3 | specialized | 16.500 | 13.371 | 0.006245 |
| 4 | specialized | 17.996 | 12.804 | 0.006967 |
| 5 | specialized | 16.239 | 11.715 | 0.006375 |
| 0 | layered | 4.775 | 4.403 | 0.006627 |
| 1 | layered | 4.776 | 4.311 | 0.006666 |
| 2 | layered | 5.075 | 4.736 | 0.006707 |
| 3 | layered | 4.849 | 4.228 | 0.006806 |
| 4 | layered | 4.827 | 4.781 | 0.007284 |
| 5 | layered | 5.057 | 4.538 | 0.006804 |

## Median current DB call (ms)

| Pattern | Path | Frozen legacy SQL | Bound AST SQL |
|---|---|---:|---:|
| 0 | specialized | 5.454 | 5.999 |
| 1 | specialized | 5.774 | 6.345 |
| 2 | specialized | 8.229 | 8.828 |
| 3 | specialized | 6.348 | 6.909 |
| 4 | specialized | 7.048 | 7.813 |
| 5 | specialized | 8.494 | 9.161 |
| 0 | layered | 2.176 | 2.229 |
| 1 | layered | 2.323 | 2.372 |
| 2 | layered | 2.364 | 2.395 |
| 3 | layered | 2.352 | 2.369 |
| 4 | layered | 2.431 | 2.466 |
| 5 | layered | 2.274 | 2.294 |

## Reuse boundary

Each path has a process-local LRU cache of at most 128 compiled templates. Keys snapshot ordered specification indices, source types, visit flags, chain edge/node types and directions, plus relevant structural flags. Origin/frontier/seen IDs, budget and depth are bound values. Seen-empty behavior is a boolean parameter, so empty/nonempty seen sets share one plan. Numeric budget expressions cast the same Int64 budget slot to Numeric. Cached values retain SQL, fixed constants and parameter metadata; they do not retain ASTs. Cache misses compile normally.

Three dedicated tests count compile_sql calls, check changed request parameters reuse one SQL string, check parameter independence and verify structural changes select different plans. The complete SQL suite passes 160 tests, and all 13 topology tests pass (including 145 query comparisons and 72 complete traversal comparisons).

These results demonstrate client-side reuse on small regression queries; they are not a production throughput result. The historical construction-profile.txt describes the baseline rebuild implementation.

## Reproduce

From the TTG checkout with its Jac runtime and PostgreSQL distribution configured:

```sh
jac test jac/tests/runtimelib/test_ttg_sql_bind.jac -v
jac test jac/tests/runtimelib/test_topology_index.jac -v
jac test jac/tests/runtimelib/bench_ttg_sql.jac --filter "SQL performance measurements" -v
```

Raw current measurements are results.json; historical measurements are baseline-results.json. Query patterns are defined in _sql_comparison_specs in test_topology_index.jac.
