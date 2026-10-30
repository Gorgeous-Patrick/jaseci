# Dependency-guided prefetch validation

Validated on 2026-10-30 using the Python CPU backend and isolated PostgreSQL 18.6.
Implementation branch: `feat/ttg-dependency-graph`.

## PostgreSQL-backed integration results

| Case | Submitted IDs | Raw-cache promotions | Foreground result |
| --- | ---: | ---: | --- |
| Outgoing C branch | 3 | 3 | c0, c1, c2 |
| Incoming D branch | 3 | 3 | d0, d1, d2 |
| Budget 2 | 2 | 2 | All 3 selected labels |
| Two selected visit sites | 6 | 6 | All 6 C/D labels |
| Worker failure | 3 | 0 | All 3 selected labels through demand fallback |
| Selected-path SQL failure | 0 | 0 | All 3 selected labels through demand fallback |

The outgoing and incoming branch cases submit zero IDs from the unselected
branch and zero IDs behind the decoy edge. Each case uses a fresh execution
context over a persisted fixture. The fixture also exercises node and edge
subtypes. Repeated stable hooks produce one origin/hop resolution plan.

Additional cases validate cancellation, ordinary configured spawn, a combined
completion event for outstanding batches, and preservation of an earlier inserted
value after a speculative PostgreSQL error.

The tests are in `jac/tests/runtimelib/test_ttg_dependency_prefetch.jac`;
fixtures are in `jac/tests/runtimelib/fixtures/ttg_prefetch_walkers.jac`.

## Checks

- Nine selective-prefetch cases passed.
- The targeted runtime regression set passed 85 tests with zero failures.
- Eleven static file checks passed with zero errors. Dynamic-boundary and
  unknown-type warnings remain in this prototype.
- Eleven files passed `jac fmt --check --lintfix`.
- Design documentation, the release fragment and validation report passed Markdown
  lint. `git diff --check` passed.

Run the targeted runtime set from the repository root with a working PostgreSQL
runtime or the project's configured embedded PostgreSQL distribution:

```sh
jac test \
  jac/tests/runtimelib/test_ttg_dependency_prefetch.jac \
  jac/tests/runtimelib/test_ttg_checkpoints.jac \
  jac/tests/runtimelib/test_ttg_dependencies.jac \
  jac/tests/runtimelib/test_ttg_queue_dependencies.jac \
  jac/tests/runtimelib/test_ttg_queue_execution.jac \
  jac/tests/runtimelib/test_ttg_sql_bind.jac \
  jac/tests/runtimelib/test_osp_kernel.jac \
  jac/tests/runtimelib/test_osp_kernel_sv.jac \
  jac/tests/runtimelib/test_prefetch_policy.jac \
  jac/tests/runtimelib/test_topology_index.jac \
  jac/tests/runtimelib/test_pgwire.jac
```

The broader Python emitter suite has a separately reproduced baseline failure:
`native test shims lower identically via splice` expects `invoke_native_test`
in a generated AST. Both the clean tracked base `e0db3d8e7` and the automatic-hook
implementation produced 26 passes and that same failure.

## Evaluation boundaries

These results establish selected-path resolution, foreground correctness and real
raw-cache consumption. Current-policy latency, DB-call time and SQL-command
comparisons are the next measurement stage.

Profiling must include SAVEPOINT/RELEASE, selected-path ID lookup, payload loading,
reader cleanup and normal demand lookup. The per-plan resolution timer includes
SQL construction and locking as well as execution. Driver-boundary DB-call time
is a separate measurement.

See [mechanism and API](README.md) and the
[English presentation](../../presentations/ttg-dependency-prefetch/README.md).
