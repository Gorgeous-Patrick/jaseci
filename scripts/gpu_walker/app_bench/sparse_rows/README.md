# Sparse row aggregation

Each row is a small Jac graph: a zero-valued root has an outgoing `Member` edge
to each nonzero value. One `RowSum` walker begins at each root, adds every value,
and counts visits. Rows have zero to 64 members, so adjacent GPU threads may
perform very different amounts of work. This is a graph aggregation workload,
not a dense or sparse matrix multiplication implementation.

The benchmark compares complete serial Jac traversal with the public Jac GPU
runtime on the same graph and batch. It generates four deterministic cases from
128 to 4,096 rows. A direct sum over the generated values is the independent
oracle. Every serial and GPU result is checked against that oracle on every
round, and every GPU status must be zero. Fresh walkers prevent prior rounds from
affecting later ones. Both arms run in randomized order for three warmups and
15 measured pairs. Medians and all per-round samples go to `results.json`; a
compact table goes to `comparison.csv`. Graph construction and GPU runtime setup
are reported separately. The GPU interval includes packing, allocation or reuse,
transfers, execution, and copyback. This app does not isolate kernel time.
Walker creation is outside both measured intervals.

Use the Jac Python backend from the repository root. The `plan` action only
prints the planned cases:

```bash
jac run --backend python scripts/gpu_walker/app_bench/sparse_rows/benchmark.jac plan --output /tmp/jac-sparse-rows
```

The command below is for a future explicitly requested run on a Linux NVIDIA
machine with the repository's Jac GPU compiler. It has not been executed:

```bash
jac run --backend python scripts/gpu_walker/app_bench/sparse_rows/benchmark.jac run --output /tmp/jac-sparse-rows
```

The directory must be new. No previous measurements are reused. A ratio below
one means the GPU public runtime is slower than serial Jac for that case. This
measures application cost, unlike the kernel-only layout experiment in
[`layout_bench`](../../layout_bench/README.md).
