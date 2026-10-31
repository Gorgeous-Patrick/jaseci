# Jac GPU application benchmarks

These four Jac applications measure the **public GPU runtime call** against
ordinary serial Jac traversal on the same generated graph and query batch.
They complement the [matrix multiplication layout benchmark](../layout_bench/README.md),
which measures GPU kernel time while changing only physical node placement.
No new GPU measurements were collected while adding these applications.

| Application | Graph and question | Jac program and protocol |
| --- | --- | --- |
| Hierarchical monitoring | Shared site/building/device trees; thresholded subtree counts, totals, and alerts | [hierarchy](hierarchy/README.md) |
| Dependency analysis | Shared finite dependency DAGs; aggregate scores with repeated arrivals | [dependency](dependency/README.md) |
| Event sequence scoring | Independent event chains; conditional weighted risk scores | [sequence](sequence/README.md) |
| Sparse row aggregation | Irregular fanout; one sum and visit count per row | [sparse rows](sparse_rows/README.md) |

Each app defines the actual traversal in Jac. Its benchmark creates real graph
objects, computes an independent arithmetic oracle, checks serial Jac against
that oracle, then checks every GPU result, publication into walker fields, and
status after each call. Fresh walkers avoid state leaking between rounds. Each
case retains raw paired samples. The default protocol uses three warmup rounds and
15 measured rounds,
seeded randomized CPU/GPU order, separate graph creation and runtime setup
times, and source provenance. No minimum speedup is required; a ratio below 1
is a GPU regression.

The reported GPU interval includes the public runtime's graph packing, device
transfers, kernel execution, result copyback, and publication. It is deliberately
different from a kernel-only timing and should not be compared directly with
the layout benchmark's microsecond kernel medians. Graph creation and Jac PTX
setup are listed separately. These apps do not yet include a fixed handwritten
CUDA reference or a random-versus-predicted layout arm. The existing [subtree
study](../subtree_query/README.md) has a separate handwritten CSR reference.

From the repository root, use each app's `plan` action to inspect intended
cases, or an explicit `run` on a supported Linux NVIDIA host. The four paths
are `hierarchy`, `dependency`, `sequence`, and `sparse_rows`. Example:

```bash
jac run --backend python scripts/gpu_walker/app_bench/sparse_rows/benchmark.jac plan --output /tmp/jac-sparse-rows
```

No app, test, plan command, benchmark, graph preparation, compiler, or GPU
workload was executed while preparing this change. The code requires review and
execution on the intended host before its GPU behavior or timing can be claimed
as verified. The output directory must be new for every run.
