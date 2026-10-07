# Transformer tensor execution evidence - 2026-10-06

These 65 recovered files preserve the original CPU/CUDA validation, measurement,
profiling and smoke-test records without content changes. The SHA-256 manifest
and this README were added during recovery.

- [Architecture, reproduction commands and interpretation](../README.md)
- [CPU validation](validation_cpu.json), [CUDA validation](validation_cuda.json)
- [CPU benchmark](benchmark_cpu.json), [CUDA benchmark](benchmark_cuda.json)
- [Summary](summary.json), [timing table](timing_table.md)
- [Original CPU graph](tensor_cpu.dot), [rewired CPU graph](tensor_cpu_rewired.dot)
- [Original CUDA graph](tensor_cuda.dot), [rewired CUDA graph](tensor_cuda_rewired.dot)
- [Profiler traces and CPU profiles](profiles/)
- [Smoke-test records](smoke_cpu/), which are not used for performance conclusions
- [SHA-256 manifest](artifact-sha256.json), excluding itself and this README

Recorded CUDA results came from an RTX 3090 with PyTorch 2.8.0+cu128. The Jac
walker schedules the real module graph on the host; tensor math runs on the
selected device. Jac did not outperform the equivalent PyTorch eager or compiled
baselines in these experiments. Profiling traces are separate instrumented runs,
not a decomposition of the unprofiled latency measurements.

Absolute paths inside raw JSON and profiles refer to the original machine. Trace
files are archived under `profiles/`, and smoke artifacts under `smoke_cpu/`.
Re-running validation should use a separate `--output` directory to preserve this
historical evidence. Regenerate the timing table from saved benchmark JSON with
`python3 jac/examples/transformer_graph/analyze_tensor_results.py`.
