# Running the Jac GPU benchmarks

This guide covers running the benchmarks in this PR. All suites were first run
on an RTX 3090 on 2026-11-02; the results and their interpretation are in
[`GPU_BENCHMARK_RESULTS.md`](GPU_BENCHMARK_RESULTS.md). On a new host or
revision, still treat the first GPU run as an integration check before drawing
performance conclusions.

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
binary from this source tree if the host does not already have a working
source environment (see [`jac/README.md`](jac/README.md#building-from-source)).
No root access is needed. With [Zig](https://ziglang.org/download/) 0.16.0 on
`PATH`:

```bash
cd jac
zig build fetch-llvm   # pinned LLVM subset for the NVPTX shim
zig build -Ddev        # builds CPython 3.14 and jac/zig-out/bin/jac
cd ..
export PATH="$PWD/jac/zig-out/bin:$PATH"
```

The `-Ddev` binary runs this checkout's compiler directly, which is what the
runners require. The first build takes roughly ten minutes; the first `jac`
command afterwards also spends a minute compiling and caching the compiler.
The bundled interpreter provides Python 3.14, so the host's system Python
version does not matter. Keep assertions enabled: do not use `python -O` or
`PYTHONOPTIMIZE`.

The source environment must make NumPy and Matplotlib importable to the Jac
launcher. For the repository's bundled `jac` binary, install them in its
interpreter with `jac install numpy matplotlib --global`. The benchmark runners
do not install dependencies themselves.

## Check the tools before measuring

The CUDA toolkit is often installed without being on `PATH` (for example under
`/usr/local/cuda-12.9`). Add its `bin` directory first:

```bash
export PATH=/usr/local/cuda-12.9/bin:$PATH
```

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
Do not change driver permissions just to obtain counters. On GeForce cards
such as the RTX 3090, expect `ERR_NVGPUCTRPERM`; the report then states that
counters were unavailable. The CUDA 12.9 toolchain needs a driver from the
575 series or newer (the reference run used 595.71). The application
suite needs the public GPU runtime and CUDA driver; it does not use the
layout suite's Nsight kernel trace or handwritten CUDA reference.

Read the GPU name, free memory, and other GPU processes in `nvidia-smi` before
and after the run. Prefer an otherwise idle GPU. Shared machines may show
other users' processes holding memory; that is acceptable if their utilization
stays near 0%. If you have root, lock clocks for steadier absolute times
(`sudo nvidia-smi -pm 1` and `sudo nvidia-smi -lgc <MHz>`); without root,
rely on the randomized arm order and report that clocks were not locked. Do not mix runs across host,
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
layout tests. These are correctness checks, not GPU performance results. On the
reference run all layout tests and all six application test files passed.

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

On a remote host, start the whole sequence detached so a dropped SSH
connection does not kill it, for example
`setsid nohup ./run_all.sh > run_all.log 2>&1 < /dev/null &`, where
`run_all.sh` holds the commands above. On the reference 3090 the six
application suites took about four minutes in total and the layout suite
about one minute, after a five-minute test pass.

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
samples when sharing a result. Record each new run alongside the reference
results in [`GPU_BENCHMARK_RESULTS.md`](GPU_BENCHMARK_RESULTS.md) rather than
pooling timings across runs. The GPU compiler-pass feasibility discussion is
separate from these runtime benchmarks; see
[`COMPILER_GPU_FEASIBILITY.md`](scripts/gpu_walker/COMPILER_GPU_FEASIBILITY.md).
