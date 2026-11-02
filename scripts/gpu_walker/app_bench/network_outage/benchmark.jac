"""Plan or measure end-to-end outage impact queries on a network snapshot."""

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
import from model { NetworkAsset, PropagatesTo, OutageImpact }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob HERE: Path = Path(__file__).resolve().parent,
     ROOT: Path = HERE.parents[3],
     CASES: list[tuple[str, int, int, int, int, int]] = [
         ('campus', 1, 4, 8, 2, 32),
         ('metro', 4, 6, 8, 2, 256),
         ('regional', 8, 8, 8, 2, 1024)
     ],
     WARMUP: int = 3,
     REPEATS: int = 15;

def sha(path: Path) -> str {
    return hashlib.sha256(path.read_bytes()).hexdigest();
}

def write_json(path: Path, data: any) {
    path.write_text(json.dumps(data, indent=2) + '\n');
}

def topology(cores: int, regions_per_core: int, access_per_region: int, endpoints_per_access: int) -> tuple[list[int], list[int], list[int], list[list[tuple[int, bool]]], list[list[int]]] {
    # Raw directed links include flags for independently powered backups.
    kinds: list[int] = [];
    households: list[int] = [];
    criticality: list[int] = [];
    links: list[list[tuple[int, bool]]] = [];
    groups: list[list[int]] = [[], [], [], []];
    for core in range(cores) {
        core_index = len(kinds);
        kinds.append(0);
        households.append(0);
        criticality.append(0);
        links.append([]);
        groups[0].append(core_index);
        for region in range(regions_per_core) {
            region_index = len(kinds);
            kinds.append(1);
            households.append(0);
            criticality.append(0);
            links.append([]);
            groups[1].append(region_index);
            links[core_index].append((region_index, False));
            for access in range(access_per_region) {
                access_index = len(kinds);
                kinds.append(2);
                households.append(40 + ((core * 71 + region * 17 + access * 29) % 121));
                criticality.append(0);
                links.append([]);
                groups[2].append(access_index);
                links[region_index].append((access_index, (core + region + access) % 7 == 0));
                for endpoint in range(endpoints_per_access) {
                    endpoint_index = len(kinds);
                    kinds.append(3);
                    households.append(0);
                    criticality.append((core * 5 + region * 3 + access * 7 + endpoint) % 4);
                    links.append([]);
                    groups[3].append(endpoint_index);
                    links[access_index].append((endpoint_index, (core + region + access + endpoint) % 5 == 0));
                }
            }
        }
    }
    return (kinds, households, criticality, links, groups);
}

def queries(groups: list[list[int]], count: int) -> tuple[list[int], list[int]] {
    roots = [groups[q % 4][(q * 17 + q // 4) % len(groups[q % 4])] for q in range(count)];
    floors = [1 + (q % 3) for q in range(count)];
    return (roots, floors);
}

def oracle(households: list[int], criticality: list[int], links: list[list[tuple[int, bool]]], root_id: int, floor: int) -> tuple[list[int], int] {
    # Traverse raw links, stopping failure propagation at live backup links.
    pending = deque([root_id]);
    affected = critical = visits = 0;
    peak = 1;
    while pending {
        current = pending.popleft();
        affected += households[current];
        critical += int(criticality[current] >= floor);
        visits += 1;
        for (target, backed_up) in links[current] {
            if not backed_up {
                pending.append(target);
            }
        }
        peak = max(peak, len(pending));
    }
    return ([affected, critical, visits, floor], peak);
}

def state(wk: OutageImpact) -> list[int] {
    return [wk.affected_households, wk.critical_sites, wk.visited, wk.priority_floor];
}

def build_nodes(kinds: list[int], households: list[int], criticality: list[int], links: list[list[tuple[int, bool]]]) -> list[NetworkAsset] {
    nodes = [NetworkAsset(kind=kind, households=households[index], criticality=criticality[index])
        for (index, kind) in enumerate(kinds)];
    for (source, row) in enumerate(links) {
        for (target, backed_up) in row {
            if not backed_up {
                nodes[source] +>:PropagatesTo():+> nodes[target];
            }
        }
    }
    return nodes;
}

def plan() {
    print('PLAN ONLY: no result directory, Jac graph, or GPU call created.');
    for (name, cores, regions, access, endpoints, count) in CASES {
        print(f'{name}: {cores} cores x {regions} regions x {access} access nodes x {endpoints} endpoints, {count} queries');
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
        'question': 'full public-runtime latency for network outage blast-radius queries',
        'graph_semantics': 'directed links with live backup paths removed from the outage propagation snapshot',
        'timing_boundary': 'walkers made before timer; CPU serial spawn or GPU run_walkers inside timer; graph build and runtime setup separate',
        'python': sys.version,
        'compiler_package': str(compiler_package),
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'git_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'source_sha256': {
            **{name: sha(HERE / name) for name in ['model.jac', 'benchmark.jac', 'README.md']},
            'jac/jaclang/runtime/gpu.jac': sha(ROOT / 'jac/jaclang/runtime/gpu.jac')
        },
        'cases': []
    };
    output.mkdir(parents=True, exist_ok=False);
    write_json(output / 'results.json', results);
    try {
        for (case_index, (name, cores, regions, access, endpoints, count)) in enumerate(CASES) {
            began = time.perf_counter_ns();
            (kinds, households, criticality, links, groups) = topology(cores, regions, access, endpoints);
            nodes = build_nodes(kinds, households, criticality, links);
            build_ms = (time.perf_counter_ns() - began) / 1_000_000;
            (root_indices, floors) = queries(groups, count);
            starts = [nodes[index] for index in root_indices];
            oracle_results = [
                oracle(households, criticality, links, root_id, floor)
                for (root_id, floor) in zip(root_indices, floors)
            ];
            expected = [item[0] for item in oracle_results];
            capacity = max(item[1] for item in oracle_results);
            max_visits = max(item[0][2] for item in oracle_results);
            if max_visits > 4096 or capacity > 1024 {
                raise ValueError('Unexpected outage traversal bound; review topology before GPU use.');
            }
            active_edges = sum(1 for row in links for (_, backed_up) in row if not backed_up);
            estimated_payload = (64 * len(nodes) + 16 * active_edges
                + 96 * count + 8 * capacity * count);
            if estimated_payload > 256 * 1024 * 1024 {
                raise ValueError('Estimated CSR payload exceeds this experiment\'s 256 MiB budget.');
            }
            for (start, floor, answer) in zip(starts, floors, expected) {
                reference = OutageImpact(priority_floor=floor);
                start spawn reference;
                assert state(reference) == answer;
            }
            metadata: dict[str, any] = {
                'name': name, 'assets': len(nodes), 'active_links': active_edges,
                'backed_up_links': sum(len(row) for row in links) - active_edges,
                'cores': cores, 'regions_per_core': regions,
                'access_per_region': access, 'endpoints_per_access': endpoints,
                'queries': count, 'query_roots': root_indices, 'priority_floors': floors,
                'topology_sha256': hashlib.sha256(json.dumps([kinds, households, criticality, links],
                    separators=(',', ':')).encode()).hexdigest(),
                'max_visits': max_visits, 'queue_capacity': capacity,
                'estimated_payload_bytes': estimated_payload,
                'graph_build_ms': build_ms, 'records': [], 'complete': False
            };
            results['cases'].append(metadata);
            write_json(output / 'results.json', results);

            began = time.perf_counter_ns();
            with GpuWalkerRuntime(OutageImpact, graph_format='csr',
                queue_capacity=capacity, max_visits=max_visits) as gpu {
                metadata['gpu_setup_ms'] = (time.perf_counter_ns() - began) / 1_000_000;
                execution: any = None;
                for (phase, rounds) in [('warmup', WARMUP), ('measured', REPEATS)] {
                    for pair in range(rounds) {
                        order = ['cpu', 'gpu'];
                        random.Random(419 + case_index * 1000 + pair + (10000 if phase == 'measured' else 0)).shuffle(order);
                        for arm in order {
                            walkers = [OutageImpact(priority_floor=value) for value in floors];
                            began = time.perf_counter_ns();
                            if arm == 'cpu' {
                                for (start, wk) in zip(starts, walkers) {
                                    start spawn wk;
                                }
                            } else {
                                execution = gpu.run_walkers(walkers, starts);
                            }
                            duration_ms = (time.perf_counter_ns() - began) / 1_000_000;
                            actual = [state(wk) for wk in walkers];
                            assert actual == expected;
                            if arm == 'gpu' {
                                assert execution.gpu_executed;
                                assert execution.status == [0] * count;
                                assert execution.fields['affected_households'] == [row[0] for row in expected];
                                assert execution.fields['critical_sites'] == [row[1] for row in expected];
                                assert execution.fields['visited'] == [row[2] for row in expected];
                                assert execution.fields['priority_floor'] == [row[3] for row in expected];
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
            }
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
