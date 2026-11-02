# Benchmark specification: Jac GPU node layout

Status: implementation specification, October 30, 2026. No new performance
measurements have been collected for this benchmark.

The benchmark entry point, evidence validation/reporting, and CPU-only tests are
implemented in Jac. Existing Python compiler/CUDA research helpers remain reused
dependencies, and the independent handwritten performance reference remains CUDA.

## Question and scope

Does the access order exposed by Jac's named cursors enable a useful GPU node
layout, while preserving the program's behavior?

This benchmark implements the first deliverable in the existing
[research contract](../layout_study/RESEARCH_CONTRACT.md): full-output int64
matrix multiplication. It reuses the real Jac graph builder, production packer,
checked LLVM lowering, CUDA reference, and trace auditor already in this branch.
It prepares fresh inputs and validates freshly generated code rather than
requiring equality with a historical compiler artifact.

The optional subtree extension remains outside this first benchmark. The broader
[runtime research goal](../runtime.md#general-graph-storage-experiment-2026-09-30)
also requires graph workloads and application-cost evaluation. Results from this
suite alone do not complete that broader research agenda.

## Required experiment

| Arm | Layout | Compiler policy | Purpose |
| --- | --- | --- | --- |
| Jac before | Random physical node IDs, seed 928 | Checked standard LLVM O2 | Layout baseline |
| Jac after | Complete cursor-a discovery BFS, then complete cursor-b discovery BFS; preserve first occurrence | The identical checked O2 PTX and loaded function | Proposed layout |
| CUDA reference | Dense matrices | Fixed 16-by-16 tiled int64 kernel, nvcc O3 | Performance reference |

Random seeds 929 and 930 are supporting repetitions in the same experiment.
The primary comparison always uses seed 928; do not select the fastest seed.
LLVM O2 and nvcc O3 are different optimizing pipelines, not equivalent flags.

Use exactly these M-by-K-by-N shapes: `3x5x2`, `17x31x19`, `64x128x64`,
`128x128x128`, and `256x256x256`. Every launch computes all M*N outputs.
Input values are `A[i,q] = (i+q)%7-3`, `B[q,j] = (3*q+j)%11-5`.
The bound `15*K` keeps all products and partial sums within signed int64.

Between the Jac arms, hold source, PTX, logical identities, values, adjacency
order, starting nodes, initial state, lane order, thread mapping, launch geometry,
queue capacity, visit bound, and output coverage constant. Only physical node
IDs and their consistent remapping change. Use 128 threads per Jac block.
The CUDA reference keeps its fixed 16-by-16 block geometry across all cases.

## Correctness gates

1. Build real Jac objects and save production-packed arrays. Check the independent
   arithmetic oracle for every output; the existing builder additionally checks
   representative serial Jac walkers. These sampled serial checks are not a CPU
   performance baseline.
2. Audit every permutation as a bijection. Verify fields, tags, CSR rows/targets,
   heads, queue initialization, and every lane's logical cursor arrivals.
3. Emit baseline and checked O2 from the same raw LLVM module. Run the existing
   13 valid/error fixtures against the production host JIT and both freshly
   emitted GPU kernels before performance measurement. Preserve all checks.
4. Before every timed graph replay, poison outputs and Jac statuses outside the
   timer. After the replay, verify every output and every status outside timing.
5. Save hashes of sources, inputs, permutations, LLVM, PTX, traces, and results.
   Reject missing, mismatched, incomplete, or incorrectly joined evidence.

Validation code uses assertions in existing helpers. The entry point must reject
optimized Python (`-O` / `PYTHONOPTIMIZE`) so these checks remain active.

## Measurement protocol

Use one randomized interleaved Nsight Systems run containing all five arms,
with three warmup rounds, 15 measured rounds, and 16 sequential CUDA graph nodes
per replay. Arm-order seed is 237. The primary statistic is the median actual
kernel end-minus-start duration, in microseconds, from node tracing. Retain all
samples, p10/p90, extrema, and per-round means. Audit every traced kernel,
including primes and warmups, against the requested arm order and geometry.
Before publishing, validate unique case/arm/phase/round/node identities and
recompute every timing summary from its raw samples. Reject inconsistent
medians, extrema, percentiles, or round means; positive-looking summary values
alone are not evidence. Apply the same consistency check to ordinary-event
summaries and their replay records.

Collect a separate ordinary CUDA-event run with five warmup rounds and 25
measured rounds, also 16 nodes per replay. Event intervals include graph
scheduling gaps; they must never substitute for the primary kernel statistic.
Sequential nodes within a replay are correlated observations, not independent
experimental rounds.

Compilation, graph construction, packing/remapping, allocation, host/device
transfers, output poisoning, and correctness checks are outside kernel timing.
Retain preparation costs and per-arm upload/capture and copyback/validation
diagnostics separately. These are not a measured public-runtime end-to-end
latency or a CPU-versus-GPU speedup.

Require the loaded Jac compiler to resolve to this checkout before execution.
Record device snapshots, free memory, tool versions (including loaded LLVM), source revision and dirty
state, and commands. Check planned allocations against available VRAM. Preserve
evidence of competing GPU processes. Attempt an Nsight Compute counter probe
separately; missing tooling or denied counters must be recorded accurately and
must not trigger changes to machine or driver settings. Logical address-segment
analysis is supporting modeled evidence, not measured memory transactions.

## Required outputs and acceptance

- `comparison.csv` and `comparison.json`: five rows, the three primary medians,
  layout speedup `T_before / T_after`, and residual gap `T_after / T_CUDA`.
- Raw traces, launch audit, samples/distributions, seed repetitions, packed
  inputs, permutations, code-generation artifacts, and fresh status validation.
- `REPORT.md` and a compact white-background, sans-serif English `REPORT.pdf`
  that derive conclusions from the new data, including regressions. Both reports
  and the comparison JSON identify the exact run by start time, output directory,
  and primary trace hash; a PTX hash alone cannot distinguish repeated runs.
- `commands.json`: exact commands, stage outcomes, source hashes, versions, and
  a completion marker written only after required stages succeed.

The old same-trace pilot remains linked as historical context; it is not pooled
with new measurements. The new runner must not require the old 3000-cubed
artifacts or reuse an old report's numerical conclusions.

Correctness and reproducibility are mandatory. No minimum speedup is assumed.
The tiled reference compares complete implementations; its gap also reflects
dense indexing and shared-memory reuse, so it is not solely compiler overhead.

## Requirement traceability

The [research contract](../layout_study/RESEARCH_CONTRACT.md) defines the matmul
question and acceptance conditions. This specification fixes the existing
study's shapes, seeds, and repetition counts for reproducible new runs.

| Requirement and source | Implementation and evidence |
| --- | --- |
| Three primary groups; layout is the only Jac variable ([contract](../layout_study/RESEARCH_CONTRACT.md#objective-and-primary-groups)) | [runner](../layout_study/run.py) loads one Jac function for all layouts; saved PTX/source hashes and fixed CUDA kernel identify the comparison |
| Preserve graph identities, values, traversal, starts, and bounds ([invariants](../layout_study/RESEARCH_CONTRACT.md#jac-invariants)) | [input auditor](../layout_study/prepare.py) checks permutations and logical cursor chains; the runner repeats these checks before execution |
| Full output/status correctness and checked semantics ([acceptance](../layout_study/RESEARCH_CONTRACT.md#interpretation-and-acceptance-checks)) | [status validator](../handwritten_matmul/validate_codegen.py) compares 13 fixtures against the host JIT; replay checks compare every output with the independent matrix oracle |
| Randomized same-run actual kernel measurements, distributions, supporting seeds ([measurement](../layout_study/RESEARCH_CONTRACT.md#measurement-and-outcomes)) | [Jac stage plan](benchmark.jac), [trace auditor](../layout_study/analyze.py), and [report validator](results.jac) preserve and check requested order, geometry, samples, and summaries |
| Report both ratios, regressions, exact provenance, and measurement boundaries ([acceptance](../layout_study/RESEARCH_CONTRACT.md#interpretation-and-acceptance-checks)) | [Jac reporting](results.jac) produces CSV/JSON/Markdown/PDF from validated evidence; timing excludes preparation and transfer costs |
| Attempt counters and distinguish modeled addresses from measured hardware behavior ([acceptance](../layout_study/RESEARCH_CONTRACT.md#interpretation-and-acceptance-checks)) | [counter probe](../layout_study/counter_probe.py) records availability; [address analysis](../layout_study/address_analysis.py) labels its model separately |
| Document and implement without executing benchmarks (user instruction) | [Jac plan mode and tests](tests.jac) use mocked processes and synthetic records; a future GPU run is still required to establish integration correctness and performance |

## Execution policy for this task

Implement and document the benchmark without running it. A `plan` command must
print the exact future steps without loading CUDA, creating result directories,
or executing experiment subprocesses. The Jac CLI may compile/cache the harness
itself. Only explicit `run` executes the suite.
Use a new output directory and refuse to overwrite existing evidence. During
development, run only CPU unit tests with synthetic fixtures, Jac harness
compilation/syntax checks, and documentation checks. Do not run graph preparation,
GPU workload compilation, GPU validation, profiling, or performance measurement.
