"""Compare serial Jac and public GPU runtime on payment fraud screening."""

import argparse;
import from datetime { datetime, timezone }
import from hashlib { sha256 }
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
import from model { Flow, FraudScreen, LedgerEntity }

glob HERE: Path = Path(__file__).resolve().parent;
glob ROOT: Path = HERE.parents[3];
glob CASES: any = [
    ('branch-64', 64, 16, 8),
    ('regional-256', 256, 64, 32),
    ('network-1024', 1024, 256, 64)
];
glob ORDER_SEED: int = 237;

def digest(path: Path) -> str {
    return sha256(path.read_bytes()).hexdigest();
}

def write_json(path: Path, value: any) {
    path.write_text(json.dumps(value, indent=2) + '\n');
}

def require(condition: bool, message: str) {
    if not condition {
        raise ValueError(message);
    }
}

def make_case(payers: int, payees: int, maximum_transfers: int) -> any {
    """Construct the Jac graph and a separate table used by the oracle."""
    recipients = [
        LedgerEntity(kind=3, amount=0, cross_border=0, odd_hour=0,
                     watchlisted=int(index % 13 == 0))
        for index in range(payees)
    ];
    watchlisted = [int(index % 13 == 0) for index in range(payees)];
    starts: list[LedgerEntity] = [];
    rows: list[list[tuple[int, int, int, int]]] = [];
    thresholds: list[int] = [];
    transfer_count = 0;
    for payer in range(payers) {
        account = LedgerEntity(kind=1, amount=0, cross_border=0, odd_hour=0,
                               watchlisted=0);
        starts.append(account);
        thresholds.append((500, 1500, 3000)[payer % 3]);
        row: list[tuple[int, int, int, int]] = [];
        degree = (payer * 17 + 3) % (maximum_transfers + 1);
        for slot in range(degree) {
            amount = 100 + ((payer * 41 + slot * 193) % 4901);
            cross_border = int((payer + slot) % 3 == 0);
            odd_hour = int((payer * 3 + slot) % 5 == 0);
            recipient_id = (payer * 31 + slot * 7) % payees;
            transfer = LedgerEntity(kind=2, amount=amount,
                                    cross_border=cross_border, odd_hour=odd_hour,
                                    watchlisted=0);
            account +>:Flow():+> transfer;
            transfer +>:Flow():+> recipients[recipient_id];
            row.append((amount, cross_border, odd_hour, recipient_id));
            transfer_count += 1;
        }
        rows.append(row);
    }
    return starts, rows, watchlisted, thresholds, transfer_count;
}

def oracle(rows: any, watchlisted: any, thresholds: any) -> list[list[int]] {
    """Calculate expected outputs from primitive tables, without Jac traversal."""
    result: list[list[int]] = [];
    for (row, threshold) in zip(rows, thresholds) {
        flagged = 0;
        amount_total = 0;
        exposures = 0;
        for (amount, cross_border, odd_hour, recipient_id) in row {
            if amount >= threshold and (cross_border == 1 or odd_hour == 1) {
                flagged += 1;
                amount_total += amount;
            }
            exposures += watchlisted[recipient_id];
        }
        result.append([threshold, flagged, amount_total, exposures, 1 + 2 * len(row)]);
    }
    return result;
}

def output(walker: FraudScreen) -> list[int] {
    return [walker.threshold, walker.flagged_transfers, walker.flagged_amount,
            walker.watchlist_exposures, walker.visited];
}

def run_case(name: str, payers: int, payees: int, maximum_transfers: int,
             device: int, warmup: int, repeats: int) -> dict[str, any] {
    begin = time.perf_counter_ns();
    starts, rows, watchlisted, thresholds, transfer_count = make_case(
        payers, payees, maximum_transfers
    );
    construction_ms = (time.perf_counter_ns() - begin) / 1_000_000;
    expected = oracle(rows, watchlisted, thresholds);
    require(len(starts) == payers and len(rows) == payers, 'Incomplete payment graph');
    require(transfer_count == sum(len(row) for row in rows), 'Transfer count mismatch');
    capacity = max(1, max(len(row) for row in rows));
    visits = max(row[4] for row in expected);
    input_hash = sha256(json.dumps([rows, watchlisted, thresholds]).encode()).hexdigest();
    rounds: list[dict[str, any]] = [];
    rng = random.Random(ORDER_SEED + payers);
    gpu_name = '';
    payload_bytes = 0;
    begin = time.perf_counter_ns();
    with GpuWalkerRuntime(FraudScreen, graph_format='csr', device=device,
                          queue_capacity=capacity, max_visits=visits) as gpu {
        setup_ms = (time.perf_counter_ns() - begin) / 1_000_000;
        for (phase, count) in [('warmup', warmup), ('measured', repeats)] {
            for pair in range(count) {
                order = ['serial_jac', 'gpu_runtime'];
                rng.shuffle(order);
                for arm in order {
                    walkers = [FraudScreen(threshold=threshold) for threshold in thresholds];
                    begin = time.perf_counter_ns();
                    if arm == 'serial_jac' {
                        for (start, walker) in zip(starts, walkers) {
                            start spawn walker;
                        }
                        result: any = None;
                    } else {
                        result = gpu.run_walkers(walkers, starts);
                    }
                    elapsed_ms = (time.perf_counter_ns() - begin) / 1_000_000;
                    if arm == 'gpu_runtime' {
                        require(result.gpu_executed is True, 'CUDA execution was not confirmed');
                        require(result.status == [0] * payers, 'GPU walker status failed');
                        gpu_name = result.gpu_name;
                        payload_bytes = result.memory.payload_bytes();
                        for (column, field) in enumerate([
                            'threshold', 'flagged_transfers', 'flagged_amount',
                            'watchlist_exposures', 'visited'
                        ]) {
                            require(result.fields[field] == [row[column] for row in expected],
                                    f'GPU result field {field} differs from the oracle');
                        }
                    }
                    require([output(walker) for walker in walkers] == expected,
                            f'{arm} walker fields differ from the oracle');
                    rounds.append({
                        'phase': phase, 'pair': pair, 'arm': arm,
                        'elapsed_ms': elapsed_ms,
                        'all_outputs_and_statuses_checked': True
                    });
                }
            }
        }
    }
    cpu = [row['elapsed_ms'] for row in rounds
           if row['phase'] == 'measured' and row['arm'] == 'serial_jac'];
    cuda = [row['elapsed_ms'] for row in rounds
            if row['phase'] == 'measured' and row['arm'] == 'gpu_runtime'];
    require(len(cpu) == repeats and len(cuda) == repeats, 'Incomplete measured rounds');
    return {
        'case': name,
        'payers': payers,
        'payees': payees,
        'transfers': transfer_count,
        'queries': payers,
        'queue_capacity': capacity,
        'max_visits': visits,
        'total_visits_per_batch': sum(row[4] for row in expected),
        'input_sha256': input_hash,
        'graph_construction_ms': construction_ms,
        'runtime_setup_ms': setup_ms,
        'gpu_name': gpu_name,
        'device_payload_bytes': payload_bytes,
        'serial_jac_median_ms': statistics.median(cpu),
        'gpu_runtime_median_ms': statistics.median(cuda),
        'serial_over_gpu_ratio': statistics.median(cpu) / statistics.median(cuda),
        'rounds': rounds
    };
}

def main(argv: list[str] | None = None) {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument('action', choices=['plan', 'run']);
    parser.add_argument('--output', type=Path, required=True);
    parser.add_argument('--device', type=int, default=0);
    parser.add_argument('--warmup', type=int, default=3);
    parser.add_argument('--repeats', type=int, default=15);
    options = parser.parse_args(argv);
    if options.action == 'plan' {
        print('Plan only: no graph construction, result directory, or GPU execution.');
        for (name, payers, payees, maximum) in CASES {
            print(f'{name}: {payers} accounts, {payees} shared recipients, 0..{maximum} transfers/account');
        }
        return;
    }
    if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE') or options.warmup < 0 or options.repeats < 1 {
        parser.error('Assertions must be enabled; warmup must be nonnegative and repeats positive');
    }
    if sys.platform != 'linux' or sys.byteorder != 'little' {
        parser.error('GPU benchmarking requires little-endian Linux');
    }
    compiler_package = Path(jaclang.__file__).resolve().parent;
    if compiler_package != (ROOT / 'jac/jaclang').resolve() {
        parser.error(f'This benchmark requires the checked-out Jac compiler; loaded {compiler_package}');
    }
    output = options.output.resolve();
    if output.exists() {
        parser.error(f'Refusing to overwrite {output}');
    }
    record: dict[str, any] = {
        'status': 'running',
        'app': 'payment fraud screening',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'git_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'git_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'compiler_package': str(compiler_package),
        'python_version': sys.version,
        'warmup': options.warmup,
        'repeats': options.repeats,
        'order_seed': ORDER_SEED,
        'metric': 'public GPU run_walkers call including packing, transfers, execution and publication versus serial Jac',
        'source_sha256': {
            'model.jac': digest(HERE / 'model.jac'),
            'benchmark.jac': digest(HERE / 'benchmark.jac'),
            'gpu_runtime.jac': digest(ROOT / 'jac/jaclang/runtime/gpu.jac')
        },
        'cases': []
    };
    output.mkdir(parents=True, exist_ok=False);
    write_json(output / 'results.json', record);
    try {
        for (name, payers, payees, maximum) in CASES {
            record['cases'].append(run_case(name, payers, payees, maximum,
                                            options.device, options.warmup, options.repeats));
            write_json(output / 'results.json', record);
        }
        record['status'] = 'complete';
    } except BaseException as error {
        record['status'] = 'failed';
        record['error'] = str(error);
        raise;
    } finally {
        record['finished_utc'] = datetime.now(timezone.utc).isoformat();
        write_json(output / 'results.json', record);
    }
}

with entry:__main__ {
    main();
}
