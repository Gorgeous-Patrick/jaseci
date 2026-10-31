# Hierarchical monitoring benchmark

The [Jac workload](hierarchy.jac) represents sites, buildings and devices as a
shared, read-only tree. A `Monitor` walker queries one subtree. It counts devices
whose reading meets its threshold, sums those readings, and records whether any
matching device has an alert. Site and building nodes are traversed but do not
contribute readings. This extends the domain of the existing
[subtree query study](../../subtree_query/README.md).

The [benchmark runner](benchmark.jac) creates three deterministic cases: 1 site,
4 buildings and 16 devices each with 32 queries; 4 sites, 8 buildings and 32
devices each with 256 queries; and 8 sites, 8 buildings and 64 devices each with
1,024 queries. Query roots rotate between site, building and device. Thresholds
rotate through `-250`, `0`, `250` and `500`.

An independent list-based traversal calculates every expected output. Each round
uses fresh walkers and randomizes serial Jac versus public GPU runtime order.
Every output and GPU status is checked after timing. Default timing is three
warmup and 15 measured rounds. Graph construction and GPU setup/compilation are
recorded separately. The GPU batch time includes packing, transfers, kernel
execution, copyback and publication; it is an application metric, not pure
kernel time.
Queue capacity and visit bounds come from the independent oracle's largest
pending frontier and traversal, rather than the whole graph by default.

Future commands from the repository root:

```bash
jac run --backend python scripts/gpu_walker/app_bench/hierarchy/benchmark.jac plan --output /tmp/jac-hierarchy-001
jac run --backend python scripts/gpu_walker/app_bench/hierarchy/benchmark.jac run --output /tmp/jac-hierarchy-001
```

Use a fresh output directory on Linux with an NVIDIA GPU and this checkout's
Jac compiler. `results.json` preserves all round timings, source/input hashes,
correctness flags, setup costs, GPU identity, medians and failure status. This
work was not executed; GPU integration and timings remain unverified.
