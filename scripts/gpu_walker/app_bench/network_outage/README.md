# Network outage impact benchmark

This [Jac workload](model.jac) estimates the blast radius of a failed network
asset. A generated snapshot contains core, regional, and access routers plus
service endpoints. Access routers carry household counts; service endpoints
carry criticality levels. Directed links describe downstream dependence. Some
links have an independently powered backup, so a failure cannot propagate over
them. The Jac graph contains only links where the failure can propagate, while
the independent oracle reads the original links and their backup flags.

One `OutageImpact` walker starts at each failed asset. It counts exposed
households, counts exposed service endpoints at or above its priority floor, and
records the assets traversed. Queries rotate among all four asset layers and
priority floors 1, 2, and 3. This represents an outage snapshot with backup
availability already known, not live routing or a recovery simulator. Each
asset has one upstream parent in the generated topology, so a customer is not
counted twice through two paths.

The [runner](benchmark.jac) creates three deterministic cases:

| Case | Core x region x access x endpoints | Queries |
| --- | --- | ---: |
| Campus | 1 x 4 x 8 x 2 | 32 |
| Metro | 4 x 6 x 8 x 2 | 256 |
| Regional | 8 x 8 x 8 x 2 | 1,024 |

An independent FIFO oracle calculates every answer and the maximum traversal
frontier. Serial Jac is checked against it before timing. Each timed round uses
fresh walkers and checks every CPU/GPU output and GPU status. The default is
three warmup and 15 measured CPU/GPU pairs, with randomized order in each pair.
Graph creation and runtime object/PTX setup are recorded separately; the first
GPU warmup initializes the CUDA session. GPU batch
time includes packing, device transfers, execution, copyback, and publication;
it is not pure kernel time. The result also records topology and source hashes,
hardware identity, raw samples, medians, and failure status.

From the repository root, on a Linux NVIDIA CUDA host using this checkout's
Jac compiler:

```bash
jac run --backend python scripts/gpu_walker/app_bench/network_outage/benchmark.jac plan --output /tmp/jac-network-outage-001
jac run --backend python scripts/gpu_walker/app_bench/network_outage/benchmark.jac run --output /tmp/jac-network-outage-001
```

The run action requires a fresh output directory. Read `results.json` only
when `complete` is true and `status` is `complete`. This workload and its tests
have not been executed; GPU integration and timing remain unverified.
