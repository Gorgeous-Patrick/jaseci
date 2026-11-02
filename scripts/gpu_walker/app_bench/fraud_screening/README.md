# Payment fraud screening benchmark

The [Jac workload](model.jac) models payer accounts, outgoing transfers and
recipient accounts as a two-hop graph. Several payers can send to the same
recipient. One `FraudScreen` walker screens an account's recent transfers. It
counts transfers over a per-account amount threshold that are cross-border or
occur at an unusual hour, sums their amounts, and counts exposures to
watchlisted recipients. Watchlist exposure is counted per transfer, including
when a recipient is shared. This is a synthetic fraud *screening* workload, not
a trained fraud detector or a measure of detection quality.

The [runner](benchmark.jac) creates three deterministic scales: 64 payer
accounts with up to 8 transfers each, 256 with up to 32, and 1,024 with up to
64. Recipient pools are shared within each case. It calculates every expected
result from independent primitive tables, then checks fresh serial Jac and
public GPU-runtime walkers against that oracle after every call. The GPU status
and returned fields are checked too. Queue capacity and visit limits follow
the maximum account fanout and exact two-hop traversal length.

Defaults are three warmup and 15 measured paired rounds with randomized arm
order. Graph construction and runtime object/PTX setup are recorded separately;
the first GPU warmup initializes the CUDA session. GPU
time covers the public `run_walkers` call, including graph packing, host/device
transfers, execution, copyback and field publication. It is not kernel-only
time. The resulting `results.json` retains individual timings, correctness,
source and input hashes, revision, GPU identity and medians. A failed run
retains a `failed` status rather than claiming completion.

From the repository root on little-endian Linux with a CUDA-capable NVIDIA
GPU and this checkout's Jac compiler:

```bash
jac run --backend python scripts/gpu_walker/app_bench/fraud_screening/benchmark.jac plan --output /tmp/jac-fraud-001
jac run --backend python scripts/gpu_walker/app_bench/fraud_screening/benchmark.jac run --output /tmp/jac-fraud-001
```

Use a fresh output path for each run. This benchmark has not been executed;
Jac compilation, GPU integration and timings remain unverified.
