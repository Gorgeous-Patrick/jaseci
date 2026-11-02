# Running the Jac GPU benchmarks

This guide is for a future run of the benchmarks in this PR. The benchmark code
was added without executing the new application workloads. Treat the first GPU
run as an integration check before drawing performance conclusions.

## Choose the host and checkout

Use a little-endian 64-bit Linux host with an NVIDIA GPU and a compatible CUDA
driver. The RTX 3090 machine is the known target: its compute capability is 8.6,
matching the layout benchmark's `sm_86` CUDA reference. The Mac laptop and M5 Pro
cannot run this CUDA path. See [NVIDIA's GPU table](https://developer.nvidia.com/cuda/gpus)
for other devices.

Use the PR head branch, not a separate Jac installation or the upstream research
PR alone. From the repository root, `git rev-parse HEAD` should identify the
revision you intend to measure and `git status --short` should ideally be empty.
On a fresh host, obtain the PR head with:

```bash
git clone --branch feat/jac-gpu-layout-benchmark --single-branch https://github.com/ayushmk7/jaseci.git
cd jaseci
```

The root [`jac.toml`](jac.toml) sets `[dev].jaclang_source = "jac"`; do not disable
it with `JAC_NO_DEV_SOURCE=1`. Every runner records its revision and source hashes
and rejects a compiler loaded from another checkout. Build the development Jac
binary from this source tree using [`jac/README.md`](jac/README.md#building-from-source)
if the host does not already have a working source environment. The project
requires Python 3.14. Keep assertions enabled: do not use `python -O` or
`PYTHONOPTIMIZE`.

The source environment must make NumPy and Matplotlib importable to the Jac
launcher. For the repository's bundled `jac` binary, install them in its
interpreter with `jac install numpy matplotlib --global`. The benchmark runners
do not install dependencies themselves.

## Check the tools before measuring

From the repository root on the GPU host, inspect the environment:

```bash
git rev-parse HEAD
git status --short
jac --version
nvidia-smi
nvcc --version
ptxas --version
nsys --version
```

The layout suite needs this checkout's Jac/LLVM NVPTX support, NumPy,
Matplotlib, `nvcc`, `ptxas`, Nsight Systems (`nsys`), and `nvidia-smi`. It was
designed around CUDA 12.9; use a toolkit and driver compatible with the device
and each other. Nsight Compute (`ncu`) is optional: the runner attempts its
counter probe and records an unavailable counter when it cannot obtain one.
Do not change driver permissions just to obtain counters. The application
suite needs the public GPU runtime and CUDA driver; it does not use the
layout suite's Nsight kernel trace or handwritten CUDA reference.

Read the GPU name, free memory, and other GPU processes in `nvidia-smi` before
and after the run. Prefer an otherwise idle GPU. Do not mix runs across host,
driver, toolkit, revision, or workload settings when interpreting a ratio.

## Inspect, then execute

Each runner has `plan` and `run` actions. `plan` prints its cases or planned
commands; it does not execute the benchmark, although Jac may compile/cache
the harness itself. `run` creates a **new** output directory, builds the
necessary inputs and code, checks correctness, and times the work. Run these
commands from the repository root in the same shell. Choose a persistent
location outside the checkout; each child path below must not exist yet.

```bash
jac_bench_root="$(pwd)/../jac-benchmark-runs/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$jac_bench_root"

jac run --backend python scripts/gpu_walker/layout_bench/benchmark.jac plan --output "$jac_bench_root/layout"
jac run --backend python scripts/gpu_walker/app_bench/hierarchy/benchmark.jac plan --output "$jac_bench_root/hierarchy"
jac run --backend python scripts/gpu_walker/app_bench/dependency/benchmark.jac plan --output "$jac_bench_root/dependency"
jac run --backend python scripts/gpu_walker/app_bench/sequence/benchmark.jac plan --output "$jac_bench_root/sequence"
jac run --backend python scripts/gpu_walker/app_bench/sparse_rows/benchmark.jac plan --output "$jac_bench_root/sparse_rows"
jac run --backend python scripts/gpu_walker/app_bench/network_outage/benchmark.jac plan --output "$jac_bench_root/network_outage"
jac run --backend python scripts/gpu_walker/app_bench/fraud_screening/benchmark.jac plan --output "$jac_bench_root/fraud_screening"
```

Before measuring, run the native Jac test blocks in each app directory and the
layout tests. These are correctness checks, not GPU performance results. The
newly added application test blocks have not yet been executed as part of
preparing this PR.

```bash
JAC_TEST_JOBS=0 jac test scripts/gpu_walker/layout_bench/tests.jac -v
for jac_bench_app in hierarchy dependency sequence sparse_rows network_outage fraud_screening; do
  JAC_TEST_JOBS=0 jac test "scripts/gpu_walker/app_bench/$jac_bench_app/tests.jac" -v || exit 1
done
```

When the environment and plans look right, run each suite explicitly. The
layout suite has a fixed protocol; the application suites default to three
warmup pairs and 15 measured CPU/GPU pairs per case.

```bash
: "${jac_bench_root:?Set jac_bench_root to a fresh output base in this shell first}"
jac run --backend python scripts/gpu_walker/layout_bench/benchmark.jac run --output "$jac_bench_root/layout"
jac run --backend python scripts/gpu_walker/app_bench/hierarchy/benchmark.jac run --output "$jac_bench_root/hierarchy"
jac run --backend python scripts/gpu_walker/app_bench/dependency/benchmark.jac run --output "$jac_bench_root/dependency"
jac run --backend python scripts/gpu_walker/app_bench/sequence/benchmark.jac run --output "$jac_bench_root/sequence"
jac run --backend python scripts/gpu_walker/app_bench/sparse_rows/benchmark.jac run --output "$jac_bench_root/sparse_rows"
jac run --backend python scripts/gpu_walker/app_bench/network_outage/benchmark.jac run --output "$jac_bench_root/network_outage"
jac run --backend python scripts/gpu_walker/app_bench/fraud_screening/benchmark.jac run --output "$jac_bench_root/fraud_screening"
```

The layout runner accepts `--nvcc`, `--ptxas`, `--nsys`, and `--ncu` when those
executables are not on `PATH`. Application runners can select a CUDA device
with `--device 0` where supported; see each app README for its exact options.
If a run fails, keep the failed directory and logs, fix the cause, and use a
fresh output path. Never relabel a failed or partial run as a result.

## Read the evidence

The layout suite writes `REPORT.md`, `REPORT.pdf`, `comparison.csv`,
`comparison.json`, profiler traces, validation records, and `commands.json`.
Its main number is **actual GPU kernel time** from Nsight Systems. Compare
Random928 with predicted node placement only at the same shape and seed; the
tiled CUDA reference answers a different whole-implementation question.
Read [the layout walkthrough](scripts/gpu_walker/layout_bench/README.md) and
[acceptance specification](scripts/gpu_walker/layout_bench/SPEC.md) before
reporting a speedup.

Each application writes `results.json` with case sizes, raw paired batch
times, medians, input/source identity, GPU identity, and correctness status.
Require top-level `status: "complete"`, all expected cases, and every output
and GPU status checked. The application GPU interval is the complete public
`run_walkers` call: graph packing, transfers, kernel execution, copyback, and
field publication. Its serial-Jac/GPU ratio below 1 is a GPU regression.
Graph construction and runtime object/PTX setup are recorded separately. The
CUDA session is created lazily on the first GPU call, so its startup cost falls
in the warmup interval. These batch milliseconds must not be directly compared
with the layout suite's
microsecond kernel durations.

Keep the full output directory, revision, hardware/software versions, and raw
samples when sharing a result. The GPU compiler-pass feasibility discussion is
separate from these runtime benchmarks; see
[`COMPILER_GPU_FEASIBILITY.md`](scripts/gpu_walker/COMPILER_GPU_FEASIBILITY.md).
