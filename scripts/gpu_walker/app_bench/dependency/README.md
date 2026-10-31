# Dependency graph application benchmark

This Jac workload models tasks that depend on other tasks. Each query begins at
one task, follows `DependsOn` edges, sums task costs, counts tasks whose severity
meets that query's threshold, and reports the number of visits. Many independent
queries share the same read-only graph. The [walker](dependency.jac) uses the
existing experimental CSR GPU path; the [benchmark runner](benchmark.jac)
constructs its inputs, checks them, and times public-runtime calls.

The graph is a finite layered DAG: edges always point to the next layer. Adjacent
tasks can share successors. **A task reached through two different paths is
visited twice**, as required by Jac's traversal semantics; totals are per
arrival, not a deduplicated task-cost or critical-path computation. An independent
index-based FIFO oracle and serial Jac agree on every query before timing. Each
GPU call must return every field with zero statuses. The runner derives the
per-walker queue and visit bounds from the oracle, then rejects unexpectedly
large values or an estimated CSR payload above 256 MiB before creating a GPU
context. The runtime still controls actual allocation against available VRAM.

| Case | Shape | Queries | Purpose |
| --- | --- | ---: | --- |
| `wide-shallow` | 4 layers × 64 tasks | 256 | Broad, short shared traversals |
| `deep-shared` | 8 layers × 32 tasks | 256 | More dependent loads and repeated arrivals |
| `irregular` | 7 layers × 64 tasks, degree 0–2 | 512 | Divergent traversal lengths |

For each case, graph construction and one serial/oracle validation pass happen
before timing. Runtime setup and compilation are reported separately. The timed
CPU call spawns a fresh batch of walkers serially. The timed GPU call invokes
`GpuWalkerRuntime.run_walkers` on an existing runtime; it includes packing,
transfers, kernel execution, copyback, and publication. Walker object creation
is outside both timers. Three warmup pairs precede 15 measured pairs; CPU/GPU
order is randomized and recorded for each pair. Every call checks all outputs;
GPU calls also check every status. The main result is the median measured public
call latency in milliseconds and the CPU/GPU ratio. This is an application
latency comparison, distinct from the kernel-only matmul layout benchmark.

The resulting `results.json` contains all paired records, workload dimensions,
queue/visit bounds, setup and construction costs, source hashes, revision, and
completion markers. Failures retain the partial evidence with `status: failed`,
an error message, and a finish timestamp; only a full run sets `complete: true`.
It uses a fresh output directory and refuses to overwrite evidence. There is no
fixed speedup threshold: regressions must remain visible.

From the repository root, on a compatible Linux NVIDIA machine:

```bash
jac run --backend python scripts/gpu_walker/app_bench/dependency/benchmark.jac plan
jac run --backend python scripts/gpu_walker/app_bench/dependency/benchmark.jac run --output /tmp/jac-dependency-001
```

The first command only prints the planned cases. The second builds graphs,
compiles and runs the Jac GPU workload, and measures it. Neither command has
been executed while adding this app. The experiment requires the checkout's Jac
compiler, working CUDA driver, and a GPU supported by the existing CSR backend.
It has no Nsight kernel trace or handwritten CUDA comparison; its question is
public-runtime latency versus serial Jac for a shared dependency DAG.
