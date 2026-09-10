# CAPRe-Style Baseline

This is a CAPRe-style baseline for the TTG experiments, not the original
CAPRe/dataClay implementation.

## Trigger Point

`JacWalker.spawn_call` and `JacWalker.async_spawn_call` install one
session-local CAPRe state for the walker run. The actual helper trigger is the
OSP walker ability entry hook, immediately before `can ... entry` body
execution on each visited node. This matches CAPRe's method-entry
instrumentation more closely than a walker-spawn-only approximation.

## Prediction Input

The baseline reuses `JacTTGGenerator._extract_visits_from_ast`, the same static
walker/ability path recovery used by TTG. This holds prediction quality constant
and isolates execution strategy. The CAPRe executor consumes the recovered
edge-chain specs directly; it does not call TTG's `_resolve_sql_visit_bfs*`
planner or the topology-index warming path.

Branch-dependent paths remain eligible because the shared TTG extractor returns
the statically visible path set without runtime predicate pruning.

## Execution Strategy

CAPRe advances every predicted path with ordinary `Store.load_full(ids)` object
loads over already-known ids. On each ability entry, the hook records a
method-entry trigger and submits the predicted path work to the background
executor; it does not run the first-hop topology resolution on the walker
thread. The background helper then loads the ordinary edge/topology rows needed
to discover concrete target object ids.

Whenever CAPRe prefetches a node, it also prefetches that node's adjacency edge
rows through the same ordinary object-load path. This mirrors Jac's split
between object materialization and graph topology cache state without using TTG's
topology snapshot. Known adjacency edge ids are loaded as a single ordinary
batch request where possible. For a dependent chain such as
`root.manager.company`, the next hop is not issued until the preceding object has
been loaded and its topology/reference identity is available.

Independent branches and collection fan-out targets are submitted to a bounded
thread pool. Duplicate in-flight or completed loads are suppressed; dependent
chains wait for the object whose identity they need instead of issuing another
load. The maximum concurrency, depth, and object count are configurable through
`[run] capre_*` fields or the `JAC_CAPRE_*` environment variables.

The executor intentionally does not use recursive CTEs, server-side graph
traversal, stored procedures, TTG topology rows, or predicate pushdown.

Because Jac stores graph topology as ordinary node and edge rows, the CAPRe-style
resolver loads edge objects with the same ordinary object-load path to discover
the next node identity. Those edge-object loads are counted as prefetch L3
traffic and application-DB round trips. Type filtering uses the arch type and
ancestry available on the ordinary loaded rows; it does not issue a separate
topology/index query, recursive CTE, or TTG traversal query to enrich type
information.

## Cache Behavior

This branch does not have a live Redis/L2 object cache in the core runtime. The
existing TTG prefetch path inserts fetched rows into `Session.__raw_mem__`, and
demand loads later promote those raw rows into L1. CAPRe uses the same
`store_raw` path. Therefore CAPRe-prefetched objects are not directly
materialized into L1; they become L1 only when demanded and promoted by
`Session.get` or `Session.batch_get`.

The historical `L2` hit counter remains zero for this runtime path.

## Metrics And Trace

CAPRe records demand/prefetch L3 request counts, useful/late/unused prefetches,
duplicate suppression, in-flight concurrency, and round trips. Actual DB bytes
are not exposed by the store API, so `bytes_available=false` and
`bytes_transferred=0` are reported.

When `JAC_PROFILE_DIR` is set, CAPRe appends `capre_trace.csv` and
`capre_metrics.jsonl` under that directory. `JAC_CAPRE_TRACE_FILE` and
`JAC_CAPRE_METRICS_FILE` can override those paths.

Outstanding tasks are drained at walker completion by default so one experiment
run cannot warm the next one. This drain occurs after walker execution; it is
reported as `capre_drain_ms`. CAPRe keeps the demand wait event open during the
run, so dynamic one-step-ahead prefetches do not cause the demand path to wait
for a whole-walker prefetch plan to finish.
