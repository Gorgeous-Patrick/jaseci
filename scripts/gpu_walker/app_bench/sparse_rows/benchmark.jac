"""Compare serial Jac and the public GPU runtime for sparse row aggregation."""

import argparse;
import csv;
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
import from model { Entry, Member, RowSum }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob HERE: Path = Path(__file__).resolve().parent;
glob ROOT: Path = HERE.parents[3];
glob CASES: list[tuple[str, int, int]] = [
    ('small-128x8', 128, 8),
    ('batch-1024x8', 1024, 8),
    ('irregular-1024x64', 1024, 64),
    ('irregular-4096x64', 4096, 64)
];
glob WARMUP: int = 3;
glob REPEATS: int = 15;

def require(ok: bool, message: str) {
    if not ok {
        raise ValueError(message);
    }
}

def digest(path: Path) -> str {
    return hashlib.sha256(path.read_bytes()).hexdigest();
}

def build_rows(row_count: int, max_members: int) -> tuple[list[Entry], list[list[int]], int] {
    starts: list[Entry] = [];
    expected: list[list[int]] = [];
    edge_count = 0;
    for row in range(row_count) {
        root = Entry(value=0);
        degree = (row * 17) % (max_members + 1);
        total = 0;
        for slot in range(degree) {
            value = ((row * 131 + slot * 19) % 101) - 50;
            if value == 0 {
                value = 1;
            }
            member = Entry(value=value);
            root +>:Member():+> member;
            total += value;
        }
        starts.append(root);
        expected.append([total, degree + 1]);
        edge_count += degree;
    }
    return (starts, expected, edge_count);
}

def serial(starts: list[Entry], expected: list[list[int]]) -> float {
    walkers = [RowSum() for _ in starts];
    begin = time.perf_counter();
    for (start, walker) in zip(starts, walkers) {
        start spawn walker;
    }
    milliseconds = (time.perf_counter() - begin) * 1000;
    require(
        ([ [walker.total, walker.visited] for walker in walkers] == expected),
        'Serial Jac differs from the independent row oracle'
    );
    return milliseconds;
}

def gpu_call(gpu: any, starts: list[Entry], expected: list[list[int]]) -> tuple[float, any] {
    walkers = [RowSum() for _ in starts];
    begin = time.perf_counter();
    result = gpu.run_walkers(walkers, starts);
    milliseconds = (time.perf_counter() - begin) * 1000;
    require(result.gpu_executed, 'CUDA kernel was not executed');
    require((result.status == [0] * len(starts)), 'GPU walker status failed');
    require(
        ([ [walker.total, walker.visited] for walker in walkers] == expected),
        'GPU walker fields differ from the row oracle'
    );
    require(
        ((result.fields['total'] == [item[0] for item in expected])
            and (result.fields['visited'] == [item[1] for item in expected])),
        'GPU returned fields differ from the row oracle'
    );
    return (milliseconds, result);
}

def run_case(gpu: any, name: str, row_count: int, max_members: int) -> dict[str, any] {
    begin = time.perf_counter();
    (starts, expected, edge_count) = build_rows(row_count, max_members);
    construction_ms = (time.perf_counter() - begin) * 1000;
    records: list[dict[str, any]] = [];
    memory: any = None;
    device: any = None;
    for (phase, count) in [('warmup', WARMUP), ('measured', REPEATS)] {
        for pair in range(count) {
            order = ['serial_jac', 'gpu_runtime'];
            random.Random(237 + pair + (10000 if phase == 'measured' else 0)).shuffle(order);
            for arm in order {
                if arm == 'serial_jac' {
                    milliseconds = serial(starts, expected);
                } else {
                    (milliseconds, result) = gpu_call(gpu, starts, expected);
                    memory = result.memory.payload_bytes();
                    device = result.gpu_name;
                }
                records.append({
                    'phase': phase, 'pair': pair, 'arm': arm,
                    'milliseconds': milliseconds, 'all_outputs_checked': True
                });
            }
        }
    }
    cpu = [r['milliseconds'] for r in records if (r['phase'] == 'measured' and r['arm'] == 'serial_jac')];
    cuda = [r['milliseconds'] for r in records if (r['phase'] == 'measured' and r['arm'] == 'gpu_runtime')];
    return {
        'case': name, 'rows': row_count, 'maximum_members': max_members,
        'edges': edge_count, 'total_node_visits': sum(item[1] for item in expected),
        'oracle_sha256': hashlib.sha256(json.dumps(expected).encode()).hexdigest(),
        'construction_ms': construction_ms, 'device': device,
        'device_payload_bytes': memory, 'records': records,
        'serial_jac_median_ms': statistics.median(cpu),
        'gpu_runtime_median_ms': statistics.median(cuda),
        'serial_over_gpu': statistics.median(cpu) / statistics.median(cuda),
        'correctness': 'every serial and GPU result checked against independent row sums'
    };
}

def main(argv: list[str] | None = None) {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument('action', choices=['plan', 'run']);
    parser.add_argument('--output', `type=Path, required=True);
    args = parser.parse_args(argv);
    if args.action == 'plan' {
        print('PLAN ONLY: no graph creation, CUDA execution, or result directory.');
        print('Public GPU runtime versus serial Jac, 3 warmups and 15 paired measured rounds.');
        for (name, rows, maximum) in CASES {
            print(f'{name}: {rows} sparse rows, 0..{maximum} members per row');
        }
        return;
    }
    require((sys.flags.optimize == 0 and not os.environ.get('PYTHONOPTIMIZE')),
            'Run with Python assertions enabled');
    require((sys.platform == 'linux'), 'The GPU application benchmark requires Linux');
    require((Path(jaclang.__file__).resolve().parent == (ROOT / 'jac/jaclang').resolve()),
            'Use this checkout\'s Jac compiler');
    output = args.output.resolve();
    require(not output.exists(), 'Refusing to overwrite an existing output directory');
    record: dict[str, any] = {
        'status': 'running', 'app': 'sparse row aggregation',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'git_revision': subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True
        ).strip(),
        'git_status': subprocess.check_output(
            ['git', 'status', '--short'], cwd=ROOT, text=True
        ),
        'python': sys.version,
        'scope': 'public runtime call, including packing, transfers, execution and copyback',
        'warmup': WARMUP, 'repeats': REPEATS, 'order_seed': 237,
        'source_sha256': {
            'model.jac': digest(HERE / 'model.jac'),
            'benchmark.jac': digest(HERE / 'benchmark.jac'),
            'gpu_runtime.jac': digest(ROOT / 'jac/jaclang/runtime/gpu.jac')
        },
        'cases': []
    };
    output.mkdir(parents=True, exist_ok=False);
    (output / 'results.json').write_text(json.dumps(record, indent=2) + '\n');
    try {
        begin = time.perf_counter();
        with GpuWalkerRuntime(RowSum, graph_format='csr', queue_capacity=64,
                              max_visits=65) as gpu {
            record['runtime_setup_ms'] = (time.perf_counter() - begin) * 1000;
            for (name, rows, maximum) in CASES {
                record['cases'].append(run_case(gpu, name, rows, maximum));
                (output / 'results.json').write_text(json.dumps(record, indent=2) + '\n');
            }
        }
        with (output / 'comparison.csv').open('w', newline='') as stream {
            columns = [
                'case', 'rows', 'maximum_members', 'edges', 'total_node_visits',
                'serial_jac_median_ms', 'gpu_runtime_median_ms', 'serial_over_gpu'
            ];
            writer: any = csv.DictWriter(stream, fieldnames=columns);
            writer.writeheader();
            for case in record['cases'] {
                writer.writerow({key: case[key] for key in columns});
            }
        record['status'] = 'complete';
    } except BaseException as error {
        record['status'] = 'failed';
        record['error'] = str(error);
        raise;
    } finally {
        record['finished_utc'] = datetime.now(timezone.utc).isoformat();
        (output / 'results.json').write_text(json.dumps(record, indent=2) + '\n');
    }
    print(f'Complete: {output / "results.json"}');
}

with entry:__main__ {
    main();
}
