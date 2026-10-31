"""Plan or measure full public-runtime calls for dependency DAG queries."""

import argparse;
import from collections { deque }
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
import from dependency { Task, DependsOn, DependencyExposure }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob HERE: Path = Path(__file__).resolve().parent,
     ROOT: Path = HERE.parents[3],
     CASES: list[tuple[str, int, int, int, bool]] = [
         ('wide-shallow', 4, 64, 256, False),
         ('deep-shared', 8, 32, 256, False),
         ('irregular', 7, 64, 512, True)
     ],
     WARMUP: int = 3,
     REPEATS: int = 15;

def sha(path: Path) -> str {
    return hashlib.sha256(path.read_bytes()).hexdigest();
}

def write_json(path: Path, data: any) {
    path.write_text(json.dumps(data, indent=2) + '\n');
}

def case_data(layers: int, width: int, irregular: bool) -> tuple[list[list[int]], list[int], list[int]] {
    """Layered finite DAG; adjacent tasks share successors in the next layer."""
    children: list[list[int]] = [[] for _ in range(layers * width)];
    costs = [1 + ((i * 7 + 3) % 17) for i in range(layers * width)];
    severities = [(i * 13 + 5) % 11 for i in range(layers * width)];
    for layer in range(layers - 1) {
        for column in range(width) {
            source = layer * width + column;
            degree = (column % 3) if irregular else 2;
            for offset in range(degree) {
                target = (layer + 1) * width + ((column + offset) % width);
                children[source].append(target);
            }
        }
    }
    return children, costs, severities;
}

def query_indices(layers: int, width: int, count: int) -> tuple[list[int], list[int]] {
    starts = [
        ((q // 3) % min(layers, 3)) * width + ((q * 17 + q // width) % width)
        for q in range(count)
    ];
    thresholds = [(q * 3) % 12 for q in range(count)];
    return starts, thresholds;
}

def oracle(children: list[list[int]], costs: list[int], severities: list[int], root: int, threshold: int) -> tuple[list[int], int] {
    """Independent index-based FIFO oracle: repeated DAG arrivals count again."""
    pending = deque([root]);
    total = risk = visits = 0;
    peak = 1;
    while pending {
        current = pending.popleft();
        total += costs[current];
        risk += int(severities[current] >= threshold);
        visits += 1;
        pending.extend(children[current]);
        peak = max(peak, len(pending));
    }
    return [total, risk, visits, threshold], peak;
}

def state(walker: DependencyExposure) -> list[int] {
    return [walker.total_cost, walker.high_risk, walker.visits, walker.threshold];
}

def build_nodes(children: list[list[int]], costs: list[int], severities: list[int]) -> list[Task] {
    nodes = [Task(cost=cost, severity=severity) for (cost, severity) in zip(costs, severities)];
    for (source, row) in enumerate(children) {
        for target in row {
            nodes[source] +>:DependsOn():+> nodes[target];
        }
    }
    return nodes;
}

def plan() {
    print('PLAN ONLY: no result directory, Jac graph, or GPU call created.');
    for (name, layers, width, count, irregular) in CASES {
        print(f'{name}: {layers} layers x {width} tasks, {count} queries, irregular={irregular}');
    }
    print(f'Each case: {WARMUP} warmup and {REPEATS} measured paired CPU/GPU calls.');
}

def run(output: Path) {
    if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE') {
        raise ValueError('Python assertions must be enabled for correctness gates.');
    }
    output = output.resolve();
    if output.exists() {
        raise ValueError(f'Refusing to overwrite {output}');
    }
    if sys.platform != 'linux' or sys.byteorder != 'little' {
        raise ValueError('Execution requires little-endian Linux with an NVIDIA CUDA GPU.');
    }
    compiler_package = Path(jaclang.__file__).resolve().parent;
    if compiler_package != (ROOT / 'jac/jaclang').resolve() {
        raise ValueError('Run with this checkout\'s Jac compiler and runtime.');
    }

    results: dict[str, any] = {
        'complete': False,
        'status': 'running',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'question': 'full public-runtime latency for repeated dependency DAG queries',
        'graph_semantics': 'FIFO arrivals; a shared task reached by two paths executes twice',
        'timing_boundary': 'walker objects made before timer; CPU serial spawn or GPU run_walkers inside timer; graph construction and runtime setup separate',
        'python': sys.version,
        'compiler_package': str(compiler_package),
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'git_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'source_sha256': {
            **{name: sha(HERE / name) for name in ['dependency.jac', 'benchmark.jac', 'README.md']},
            'jac/jaclang/runtime/gpu.jac': sha(ROOT / 'jac/jaclang/runtime/gpu.jac')
        },
        'cases': []
    };
    output.mkdir(parents=True, exist_ok=False);
    write_json(output / 'results.json', results);
    try {
        for (case_index, (name, layers, width, count, irregular)) in enumerate(CASES) {
            began = time.perf_counter_ns();
            children, costs, severities = case_data(layers, width, irregular);
            nodes = build_nodes(children, costs, severities);
            build_ms = (time.perf_counter_ns() - began) / 1_000_000;
            root_indices, thresholds = query_indices(layers, width, count);
            starts = [nodes[index] for index in root_indices];
            oracle_results = [
                oracle(children, costs, severities, root, threshold)
                for (root, threshold) in zip(root_indices, thresholds)
            ];
            expected = [item[0] for item in oracle_results];
            capacity = max(item[1] for item in oracle_results);
            max_visits = max(item[0][2] for item in oracle_results);
            if max_visits > 511 or capacity > 256 {
                raise ValueError('Unexpected DAG traversal bound; review workload before GPU use.');
            }
            edge_count = sum(len(row) for row in children);
            estimated_payload = (24 * len(nodes) + 8 + 8 * edge_count
                + 76 * count + 8 * capacity * count);
            if estimated_payload > 256 * 1024 * 1024 {
                raise ValueError('Estimated CSR payload exceeds this experiment\'s 256 MiB budget.');
            }
            for (start, threshold, answer) in zip(starts, thresholds, expected) {
                reference = DependencyExposure(threshold=threshold);
                start spawn reference;
                assert state(reference) == answer;
            }
            metadata: dict[str, any] = {
                'name': name, 'tasks': len(nodes), 'edges': edge_count,
                'layers': layers, 'width': width, 'queries': count, 'irregular': irregular,
                'query_roots': root_indices, 'thresholds': thresholds,
                'max_visits': max_visits, 'queue_capacity': capacity,
                'estimated_payload_bytes': estimated_payload,
                'graph_build_ms': build_ms, 'records': [], 'complete': False
            };
            results['cases'].append(metadata);
            write_json(output / 'results.json', results);

            began = time.perf_counter_ns();
            with GpuWalkerRuntime(DependencyExposure, graph_format='csr',
                queue_capacity=capacity, max_visits=max_visits) as gpu {
                metadata['gpu_setup_ms'] = (time.perf_counter_ns() - began) / 1_000_000;
                execution: any = None;
                for (phase, rounds) in [('warmup', WARMUP), ('measured', REPEATS)] {
                    for pair in range(rounds) {
                        order = ['cpu', 'gpu'];
                        random.Random(237 + case_index * 1000 + pair + (10000 if phase == 'measured' else 0)).shuffle(order);
                        for arm in order {
                            walkers = [DependencyExposure(threshold=value) for value in thresholds];
                            began = time.perf_counter_ns();
                            if arm == 'cpu' {
                                for (start, walker) in zip(starts, walkers) {
                                    start spawn walker;
                                }
                            } else {
                                execution = gpu.run_walkers(walkers, starts);
                            }
                            duration_ms = (time.perf_counter_ns() - began) / 1_000_000;
                            actual = [state(walker) for walker in walkers];
                            assert actual == expected;
                            if arm == 'gpu' {
                                assert execution.gpu_executed;
                                assert execution.status == [0] * count;
                                assert execution.fields['total_cost'] == [row[0] for row in expected];
                                assert execution.fields['high_risk'] == [row[1] for row in expected];
                                assert execution.fields['visits'] == [row[2] for row in expected];
                                assert execution.fields['threshold'] == [row[3] for row in expected];
                            }
                            metadata['records'].append({
                                'phase': phase, 'pair': pair, 'arm': arm,
                                'duration_ms': duration_ms, 'all_outputs_and_status_checked': True
                            });
                        }
                    }
                }
                assert execution is not None;
                metadata['gpu'] = execution.gpu_name;
                metadata['payload_bytes'] = execution.memory.payload_bytes();
            measured_cpu = [r['duration_ms'] for r in metadata['records'] if r['phase'] == 'measured' and r['arm'] == 'cpu'];
            measured_gpu = [r['duration_ms'] for r in metadata['records'] if r['phase'] == 'measured' and r['arm'] == 'gpu'];
            metadata['median_cpu_ms'] = statistics.median(measured_cpu);
            metadata['median_gpu_ms'] = statistics.median(measured_gpu);
            metadata['cpu_over_gpu'] = metadata['median_cpu_ms'] / metadata['median_gpu_ms'];
            metadata['complete'] = True;
            write_json(output / 'results.json', results);
        }
        results['complete'] = True;
        results['status'] = 'complete';
    } except BaseException as error {
        results['status'] = 'failed';
        results['error'] = str(error);
        raise;
    } finally {
        results['finished_utc'] = datetime.now(timezone.utc).isoformat();
        write_json(output / 'results.json', results);
    }
}

def main() {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument('action', choices=['plan', 'run']);
    parser.add_argument('--output', type=Path, help='Fresh evidence directory for run');
    options = parser.parse_args();
    if options.action == 'plan' {
        plan();
    } else {
        if options.output is None {
            parser.error('--output is required for run');
        }
        run(options.output);
    }
}

with entry:__main__ {
    main();
}
