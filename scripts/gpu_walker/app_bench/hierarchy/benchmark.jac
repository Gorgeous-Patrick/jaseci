"""Time verified serial Jac and public GPU monitoring batches."""

import argparse;
import jaclang;
import from datetime { datetime, timezone }
import from hashlib { sha256 }
import json;
import from pathlib { Path }
import random;
import statistics;
import subprocess;
import sys;
import time;
import from hierarchy { Asset, Child, Monitor }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob HERE: Path = Path(__file__).resolve().parent;
glob ROOT: Path = HERE.parents[3];
glob CASES: any = [
    ('one-site', 1, 4, 16, 32),
    ('four-sites', 4, 8, 32, 256),
    ('eight-sites', 8, 8, 64, 1024)
];

def make_case(sites: int, buildings: int, devices: int) -> any {
    nodes = [Asset(kind=0, reading=0, alert=False)];
    children = [[]];
    kinds = [0];
    readings = [0];
    alerts = [0];
    site_ids = [];
    building_ids = [];
    device_ids = [];
    for _ in range(sites) {
        site = len(nodes);
        site_ids.append(site);
        nodes.append(Asset(kind=1, reading=0, alert=False));
        children.append([]);
        kinds.append(1);
        readings.append(0);
        alerts.append(0);
        children[0].append(site);
        nodes[0] +>:Child():+> nodes[site];
        for _ in range(buildings) {
            building = len(nodes);
            building_ids.append(building);
            nodes.append(Asset(kind=2, reading=0, alert=False));
            children.append([]);
            kinds.append(2);
            readings.append(0);
            alerts.append(0);
            children[site].append(building);
            nodes[site] +>:Child():+> nodes[building];
            for _ in range(devices) {
                device = len(nodes);
                reading = ((device * 73 + 19) % 1001) - 500;
                alert = (device % 11 == 0);
                device_ids.append(device);
                nodes.append(Asset(kind=3, reading=reading, alert=alert));
                children.append([]);
                kinds.append(3);
                readings.append(reading);
                alerts.append(int(alert));
                children[building].append(device);
                nodes[building] +>:Child():+> nodes[device];
            }
        }
    }
    return nodes, children, kinds, readings, alerts, site_ids, building_ids, device_ids;
}

def oracle(children: any, kinds: any, readings: any, alerts: any, root: int, threshold: int) -> tuple[list[int], int] {
    pending = [root];
    head = 0;
    count = 0;
    total = 0;
    has_alert = 0;
    peak = 1;
    while head < len(pending) {
        current = pending[head];
        head += 1;
        if kinds[current] == 3 and readings[current] >= threshold {
            count += 1;
            total += readings[current];
            has_alert = max(has_alert, alerts[current]);
        }
        pending.extend(children[current]);
        peak = max(peak, len(pending) - head);
    }
    return [count, total, has_alert, head, threshold], peak;
}

def state(walker: Monitor) -> list[int] {
    return [walker.count, walker.total, int(walker.has_alert), walker.visited, walker.threshold];
}

def check_batch(walkers: any, expected: any) {
    if [state(walker) for walker in walkers] != expected {
        raise ValueError('Monitoring output disagreed with the independent oracle');
    }
}

def run_case(name: str, sites: int, buildings: int, devices: int, queries: int, device: int, warmup: int, repeats: int) -> dict[str, any] {
    start = time.perf_counter();
    nodes, children, kinds, readings, alerts, site_ids, building_ids, device_ids = make_case(sites, buildings, devices);
    graph_ms = (time.perf_counter() - start) * 1000;
    root_choices = [site_ids, building_ids, device_ids];
    roots = [root_choices[i % 3][(i // 3) % len(root_choices[i % 3])] for i in range(queries)];
    thresholds = [(-250, 0, 250, 500)[i % 4] for i in range(queries)];
    oracle_rows = [oracle(children, kinds, readings, alerts, root, threshold) for root, threshold in zip(roots, thresholds)];
    expected = [row[0] for row in oracle_rows];
    capacity = max(row[1] for row in oracle_rows);
    max_visits = max(row[3] for row in expected);
    starts = [nodes[root] for root in roots];
    input_hash = sha256(json.dumps([children, kinds, readings, alerts, roots, thresholds]).encode()).hexdigest();
    start = time.perf_counter();
    with GpuWalkerRuntime(
        Monitor, graph_format='csr', device=device,
        queue_capacity=capacity, max_visits=max_visits
    ) as gpu {
        setup_ms = (time.perf_counter() - start) * 1000;
        rounds: list[dict[str, any]] = [];
        rng = random.Random(237);
        gpu_name = '';
        for round_index in range(warmup + repeats) {
            order = ['serial_jac', 'gpu_runtime'];
            rng.shuffle(order);
            for arm in order {
                walkers = [Monitor(threshold=threshold) for threshold in thresholds];
                result: any = None;
                start = time.perf_counter();
                if arm == 'serial_jac' {
                    for root, walker in zip(starts, walkers) {
                        root spawn walker;
                    }
                    status = [0] * queries;
                } else {
                    result = gpu.run_walkers(walkers, starts);
                    gpu_name = result.gpu_name;
                    if not result.gpu_executed {
                        raise ValueError('GPU execution was not confirmed');
                    }
                    status = result.status;
                }
                elapsed_ms = (time.perf_counter() - start) * 1000;
                if status != [0] * queries {
                    raise ValueError('GPU status error');
                }
                check_batch(walkers, expected);
                if arm == 'gpu_runtime' {
                    for index, field in enumerate(['count', 'total', 'has_alert', 'visited', 'threshold']) {
                        if [int(value) for value in result.fields[field]] != [row[index] for row in expected] {
                            raise ValueError(f'GPU result field {field} disagreed with the oracle');
                        }
                    }
                }
                rounds.append({
                    'round': round_index,
                    'phase': 'warmup' if round_index < warmup else 'measured',
                    'arm': arm,
                    'batch_ms': elapsed_ms,
                    'all_outputs_and_statuses_checked': True
                });
            }
        }
        medians = {
            arm: statistics.median(record['batch_ms'] for record in rounds if record['phase'] == 'measured' and record['arm'] == arm)
            for arm in ['serial_jac', 'gpu_runtime']
        };
        return {
            'id': name,
            'sites': sites,
            'buildings_per_site': buildings,
            'devices_per_building': devices,
            'nodes': len(nodes),
            'queries': queries,
            'input_sha256': input_hash,
            'queue_capacity': capacity,
            'max_visits': max_visits,
            'total_visits_per_batch': sum(row[3] for row in expected),
            'gpu_name': gpu_name,
            'graph_construction_ms': graph_ms,
            'runtime_setup_ms': setup_ms,
            'median_batch_ms': medians,
            'serial_over_gpu_ratio': medians['serial_jac'] / medians['gpu_runtime'],
            'rounds': rounds
        };
    }
}

def main(argv: list[str] | None = None) {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument('action', choices=['plan', 'run']);
    parser.add_argument('--output', `type=Path, required=True);
    parser.add_argument('--device', `type=int, default=0);
    parser.add_argument('--warmup', `type=int, default=3);
    parser.add_argument('--repeats', `type=int, default=15);
    options = parser.parse_args(argv);
    if options.action == 'plan' {
        for name, sites, buildings, devices, queries in CASES {
            print(f'{name}: {sites} sites, {buildings} buildings/site, {devices} devices/building, {queries} queries');
        }
        return;
    }
    if sys.flags.optimize or (options.warmup < 0) or (options.repeats < 1) {
        parser.error('Assertions must be enabled; warmup must be nonnegative and repeats positive');
    }
    if sys.platform != 'linux' or sys.byteorder != 'little' {
        parser.error('GPU benchmarking requires little-endian Linux');
    }
    compiler = Path(jaclang.__file__).resolve().parent;
    if compiler != (ROOT / 'jac/jaclang').resolve() {
        parser.error(f'This benchmark requires the checked-out Jac compiler; loaded {compiler}');
    }
    output = options.output.resolve();
    if output.exists() {
        parser.error(f'Output already exists: {output}');
    }
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip();
    dirty = subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True);
    results: dict[str, any] = {
        'status': 'running',
        'app': 'hierarchical monitoring',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'source_sha256': sha256((HERE / 'hierarchy.jac').read_bytes()).hexdigest(),
        'runner_sha256': sha256(Path(__file__).read_bytes()).hexdigest(),
        'runtime_sha256': sha256((ROOT / 'jac/jaclang/runtime/gpu.jac').read_bytes()).hexdigest(),
        'compiler_package': str(compiler),
        'python_version': sys.version,
        'git_revision': revision,
        'git_status': dirty,
        'warmup': options.warmup,
        'repeats': options.repeats,
        'order_seed': 237,
        'metric': 'GPU public run_walkers batch wall time including packing, transfers and publication; serial Jac batch wall time',
        'cases': []
    };
    output.mkdir(parents=True, exist_ok=False);
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n');
    try {
        for name, sites, buildings, devices, queries in CASES {
            results['cases'].append(run_case(name, sites, buildings, devices, queries, options.device, options.warmup, options.repeats));
            (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n');
        }
        results['status'] = 'complete';
    } except BaseException as error {
        results['status'] = 'failed';
        results['error'] = str(error);
        raise;
    } finally {
        results['finished_utc'] = datetime.now(timezone.utc).isoformat();
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n');
    }
}

with entry:__main__ {
    main();
}
