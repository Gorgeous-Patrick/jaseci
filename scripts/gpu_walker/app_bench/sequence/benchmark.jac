"""Benchmark the public Jac GPU runtime on weighted event chains.

No benchmark work occurs unless the explicit `run` action is selected.
"""

import argparse;
import from datetime { datetime, timezone }
import hashlib;
import jaclang;
import json;
import os;
import from pathlib { Path }
import random;
import statistics;
import subprocess;
import sys;
import time;
import from jaclang.runtime.gpu { GpuWalkerRuntime }
import from model {
    RiskScore, expected_scores, initial_score, make_workload
}

glob CASES: tuple[tuple[int, int], ...] = (
    (64, 8), (256, 32), (1024, 64)
);
glob WARMUP: int = 3;
glob REPEATS: int = 15;
glob ORDER_SEED: int = 237;
glob HERE: Path = Path(__file__).resolve().parent;
glob ROOT: Path = HERE.parents[3];

def sha(path: Path) -> str {
    return hashlib.sha256(path.read_bytes()).hexdigest();
}

def write_json(path: Path, value: any) {
    path.write_text(json.dumps(value, indent=2) + "\n");
}

def check_equal(actual: any, expected: any, label: str) {
    if actual != expected {
        raise ValueError(f"{label} disagrees with independent oracle");
    }
}

def fresh_walkers(batch: int) -> list[RiskScore] {
    return [RiskScore(score=initial_score(lane)) for lane in range(batch)];
}

def measure_serial(starts: any, batch: int, length: int, oracle: list[int]) -> float {
    walkers = fresh_walkers(batch);
    begin = time.perf_counter_ns();
    for (start, walker) in zip(starts, walkers) {
        start spawn walker;
    }
    elapsed_ms = (time.perf_counter_ns() - begin) / 1_000_000;
    check_equal([walker.score for walker in walkers], oracle, "Serial Jac score");
    check_equal([walker.visited for walker in walkers], [length] * batch, "Serial Jac visits");
    return elapsed_ms;
}

def measure_gpu(gpu: any, starts: any, batch: int, length: int, oracle: list[int]) -> tuple[float, any] {
    walkers = fresh_walkers(batch);
    begin = time.perf_counter_ns();
    result = gpu.run_walkers(walkers, starts);
    elapsed_ms = (time.perf_counter_ns() - begin) / 1_000_000;
    if (result.gpu_executed is not True) or (result.status != [0] * batch) {
        raise ValueError("Jac GPU execution or status check failed");
    }
    check_equal(result.fields["score"], oracle, "GPU score output");
    check_equal(result.fields["visited"], [length] * batch, "GPU visit output");
    check_equal([walker.score for walker in walkers], oracle, "GPU score publication");
    check_equal([walker.visited for walker in walkers], [length] * batch, "GPU visit publication");
    return elapsed_ms, result;
}

def measure_case(batch: int, length: int, case_seed: int) -> dict[str, any] {
    begin = time.perf_counter_ns();
    starts, nodes = make_workload(batch, length);
    build_ms = (time.perf_counter_ns() - begin) / 1_000_000;
    oracle = expected_scores(nodes, batch, length);
    if len(nodes) != batch * length or len(starts) != batch {
        raise ValueError("Incomplete chain graph");
    }
    records: list[dict[str, any]] = [];
    rng = random.Random(case_seed);
    gpu_name = "";
    payload_bytes = 0;
    begin = time.perf_counter_ns();
    with GpuWalkerRuntime(RiskScore, graph_format="chain") as gpu {
        setup_ms = (time.perf_counter_ns() - begin) / 1_000_000;
        for (phase, count) in [("warmup", WARMUP), ("measured", REPEATS)] {
            for pair in range(count) {
                order = ["serial", "gpu"];
                rng.shuffle(order);
                for arm in order {
                    if arm == "serial" {
                        elapsed_ms = measure_serial(starts, batch, length, oracle);
                    } else {
                        elapsed_ms, result = measure_gpu(gpu, starts, batch, length, oracle);
                        gpu_name = result.gpu_name;
                        payload_bytes = result.memory.payload_bytes();
                    }
                    records.append({
                        "phase": phase,
                        "pair": pair,
                        "arm": arm,
                        "elapsed_ms": elapsed_ms,
                        "all_outputs_checked": True
                    });
                }
            }
        }
    }
    medians: dict[str, float] = {};
    for arm in ["serial", "gpu"] {
        samples = [r["elapsed_ms"] for r in records if r["phase"] == "measured" and r["arm"] == arm];
        if len(samples) != REPEATS {
            raise ValueError("Incomplete measured rounds");
        }
        medians[arm] = statistics.median(samples);
    }
    return {
        "batch": batch,
        "chain_length": length,
        "node_count": len(nodes),
        "node_visits_per_batch": batch * length,
        "graph_build_ms": build_ms,
        "runtime_setup_ms": setup_ms,
        "gpu_name": gpu_name,
        "device_payload_bytes": payload_bytes,
        "serial_median_ms": medians["serial"],
        "gpu_public_call_median_ms": medians["gpu"],
        "public_call_speedup": medians["serial"] / medians["gpu"],
        "records": records,
        "correctness": "Every serial and GPU output/status checked against the arithmetic oracle"
    };
}

def run_suite(output: Path) {
    if sys.flags.optimize or os.environ.get("PYTHONOPTIMIZE") {
        raise ValueError("Assertions must remain enabled in the Jac runtime");
    }
    if output.exists() {
        raise ValueError(f"Refusing to overwrite {output}");
    }
    compiler_package = Path(jaclang.__file__).resolve().parent;
    if compiler_package != (ROOT / "jac/jaclang").resolve() {
        raise ValueError(f"Loaded Jac compiler {compiler_package} is not this checkout");
    }
    if sys.platform != "linux" or sys.byteorder != "little" {
        raise ValueError("Jac GPU execution requires little-endian Linux");
    }
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip();
    git_status = subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True);
    source_hashes = {
        "model.jac": sha(HERE / "model.jac"),
        "benchmark.jac": sha(HERE / "benchmark.jac"),
        "gpu_runtime.jac": sha(ROOT / "jac/jaclang/runtime/gpu.jac")
    };
    output.mkdir(parents=True, exist_ok=False);
    record: dict[str, any] = {
        "status": "running",
        "workload": "weighted transaction event chains",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "git_revision": revision,
        "git_status": git_status,
        "compiler_package": str(compiler_package),
        "source_sha256": source_hashes,
        "python": sys.version,
        "warmup_rounds": WARMUP,
        "measured_rounds": REPEATS,
        "arm_order_seed": ORDER_SEED,
        "cases": []
    };
    write_json(output / "results.json", record);
    try {
        for (index, (batch, length)) in enumerate(CASES) {
            record["cases"].append(measure_case(batch, length, ORDER_SEED + index));
            write_json(output / "results.json", record);
        }
        record["status"] = "complete";
    } except BaseException as error {
        record["status"] = "failed";
        record["error"] = str(error);
        raise;
    } finally {
        record["finished_utc"] = datetime.now(timezone.utc).isoformat();
        write_json(output / "results.json", record);
    }
}

def main() {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument("action", choices=["plan", "run"]);
    parser.add_argument("--output", type=Path, required=True);
    args = parser.parse_args();
    if args.action == "plan" {
        print("Plan only: no graph construction or GPU execution.");
        print({"cases": CASES, "warmup": WARMUP, "repeats": REPEATS, "order_seed": ORDER_SEED});
        return;
    }
    run_suite(args.output.resolve());
}

with entry:__main__ {
    main();
}
