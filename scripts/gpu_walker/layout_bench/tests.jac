"""CPU-only tests: synthetic records, mocked subprocesses, no GPU workload compilation or CUDA execution."""
import contextlib;
import copy;
import io;
import json;
import os;
import from pathlib { Path }
import runpy;
import subprocess;
import sys;
import tempfile;
import types;
import unittest;
import from unittest.mock { patch }
import scripts.gpu_walker.layout_bench.benchmark as suite;
glob check: any = unittest.TestCase();
import scripts.gpu_walker.layout_bench.results as evidence;
def synthetic_run(warmup: any = 3, repeats: any = 15) -> any {
    run = `dict(
        complete=True,
        primary_arms=evidence.PRIMARY,
        warmup=warmup,
        repeats=repeats,
        inner=16,
        order_seed=237,
        jac_function_loaded_once_for_all_layouts=True,
        jac_compilation_policy='checked standard LLVM O2',
        reference_kernel='matmul_tiled_i64',
        nvcc_command=['nvcc', '-O3', '-arch=compute_86'],
        cases=[],
        records=[]
    );
    for (cid, shape) in evidence.CASES.items() {
        (m, _, n) = shape;
        arms = {};
        for arm in evidence.ARMS {
            arms[arm] = `dict(
                grid=[((n + 15) // 16), ((m + 15) // 16), 1]
                    if (arm == evidence.REFERENCE)
                    else [(((m * n) + 127) // 128), 1, 1],
                block=[16, 16, 1] if (arm == evidence.REFERENCE) else [128, 1, 1],
                kernel='matmul_tiled_i64'
                    if (arm == evidence.REFERENCE)
                    else 'jac_Dot_cursors_batch',
                sample_n=repeats,
                median_event_us=1.0,
                min_event_us=1.0,
                max_event_us=1.0
            );
            for (phase, count) in [('warmup', warmup), ('measured', repeats)] {
                run['records'].extend(
                    `dict(
                        `case=cid,
                        arm=arm,
                        phase=phase,
                        pair=i,
                        event_us=1.0,
                        all_outputs_and_statuses_checked=True
                    ) for i in range(count)
                );
            }
        }
        run['cases'].append(
            `dict(
                id=cid,
                shape=shape,
                lanes=(m * n),
                arms=arms,
                all_outputs_and_statuses_verified=True,
                all_node_permutations_and_logical_traversals_verified=True
            )
        );
    }
    return run;
}

def synthetic_trace -> any {
    (summaries, samples) = ([], []);
    times = `dict(zip(evidence.ARMS, [100.0, 50.0, 10.0, 90.0, 110.0]));
    for cid in evidence.CASES {
        for arm in evidence.ARMS {
            value = times[arm];
            summaries.append(
                `dict(
                    `case=cid,
                    arm=arm,
                    sample_n=240,
                    median_us=value,
                    min_us=value,
                    max_us=value,
                    p10_us=value,
                    p90_us=value,
                    pair_mean_us=([value] * 15),
                    median_pair_mean_us=value
                )
            );
        }
    }
    run = synthetic_run();
    def add_sample(cid: any, arm: any, phase: any, pair: any, node_index: any) {
        start = samples[-1]['end_ns'] + 1000 if samples else 1000;
        samples.append(
            `dict(
                launch_index=len(samples),
                `case=cid,
                arm=arm,
                phase=phase,
                pair=pair,
                graph_node=node_index,
                kernel_us=times[arm],
                kernel='matmul_tiled_i64'
                    if (arm == evidence.REFERENCE)
                    else 'jac_Dot_cursors_batch',
                start_ns=start,
                end_ns=start + int(times[arm] * 1000)
            )
        );
    }
    for `case in run['cases'] {
        for arm in `case['arms'] {
            add_sample(`case['id'], arm, 'prime', -1, 0);
        }
        for record in run['records'] {
            if (record['case'] == `case['id']) {
                for node_index in range(run['inner']) {
                    add_sample(
                        record['case'],
                        record['arm'],
                        record['phase'],
                        record['pair'],
                        node_index
                    );
                }
            }
        }
    }
    return `dict(
        status='PASS',
        summaries=summaries,
        samples=samples,
        launches_verified=7225,
        measured_launches=6000
    );
}

"""Synthetic report evidence; intentionally never invokes a benchmark stage."""
def fixture(folder: any) -> any {
    def save(name: any, value: any) -> any {
        path = folder / name;
        path.parent.mkdir(parents=True, exist_ok=True);
        if isinstance(value, `dict) {
            suite.write_json(path, value);
        } else {
            path.write_text(value);
        }
        return suite.sha(path);
    }
    save('production-inputs/inputs.json', {'synthetic': True});
    baseline = save('inputs/Dot.ptx', 'synthetic baseline');
    o2 = save('optimized-codegen/O2.ptx', 'synthetic O2');
    cg = `dict(
        production_ptx_sha256=baseline,
        optimized_ptx_sha256=o2,
        raw_ir_sha256=save('optimized-codegen/raw.ll', 'synthetic raw IR'),
        optimized_ir_sha256=save('optimized-codegen/O2.ll', 'synthetic optimized IR'),
        generator_sha256=suite.sha((suite.STUDY / 'emit_checked_o2.py')),
        validation_policy='fresh validation'
    );
    save('optimized-codegen/codegen.json', cg);
    status = `dict(
        status='PASS',
        gpu_launches_checked=26,
        ptx_sha256={'baseline': baseline, 'O2': o2},
        validator_sha256=suite.sha((suite.MATMUL / 'validate_codegen.py')),
        cases=[]
    );
    for name in evidence.STATUS_CASES {
        status['cases'].append(
            `dict(
                `case=name,
                expected_status=[0],
                expected_results=[42],
                variants={
                    v: {'pass': True, 'status': [0], 'results': [42]}
                    for v in ['baseline', 'O2']
                }
            )
        );
    }
    save('optimized-codegen/status-validation.json', status);
    inputs = `dict(
        source_manifest=str((folder / 'production-inputs/inputs.json')),
        source_manifest_sha256=suite.sha((folder / 'production-inputs/inputs.json')),
        generator_sha256=suite.sha((suite.STUDY / 'prepare.py')),
        source_jac_sha256=suite.sha(
            (suite.ROOT / 'jac/examples/gpu/named_cursors.jac')
        ),
        ptx_sha256=baseline,
        cases=[]
    );
    for (cid, shape) in evidence.CASES.items() {
        digest = save(
            f'inputs/{cid}/synthetic.bin', 'synthetic arrays, never executed'
        );
        info = {'file': 'synthetic.bin', 'sha256': digest};
        layouts = [
            `dict(
                name=name,
                queue_capacity=1,
                max_visits=20,
                identity_order=info,
                files=[info],
                audit={
                    'all_node_fields_edges_heads_and_queue_remap_verified': True,
                    'all_lane_cursor_arrivals_logically_identical': True
                }
            ) for name in ['before', 'after', 'random929', 'random930']
        ];
        inputs['cases'].append(
            `dict(id=cid, shape=shape, expected=info, layouts=layouts)
        );
    }
    save('inputs/inputs.json', inputs);
    for (directory, warmup, repeats) in [
        ('optimized-profile', 3, 15),
        ('optimized-ordinary', 5, 25)
    ] {
        save((directory + '/matmul.ptx'), 'synthetic CUDA reference');
        run = synthetic_run(warmup, repeats);
        run.update(
            gpu='SYNTHETIC UNIT TEST', gpu_before='SYNTHETIC', gpu_after='SYNTHETIC'
        );
        for (path, key) in [
            ((suite.STUDY / 'run.py'), 'runner_sha256'),
            ((suite.STUDY / 'prepare.py'), 'prepare_sha256'),
            ((suite.MATMUL / 'benchmark.py'), 'driver_sha256'),
            ((suite.STUDY / 'RESEARCH_CONTRACT.md'), 'contract_sha256'),
            ((folder / 'inputs/inputs.json'), 'input_manifest_sha256'),
            ((folder / 'optimized-codegen/codegen.json'), 'optimized_codegen_sha256'),
            (
                (folder / 'optimized-codegen/status-validation.json'),
                'status_evidence_sha256'
            ),
            ((folder / 'optimized-codegen/O2.ptx'), 'jac_ptx_sha256'),
            ((suite.MATMUL / 'matmul.cu'), 'reference_source_sha256'),
            ((folder / directory / 'matmul.ptx'), 'reference_ptx_sha256')
        ] {
            run[key] = suite.sha(path);
        }
        save((directory + '/results.json'), run);
    }
    save('optimized-profile/trace.sqlite', 'synthetic trace placeholder');
    save('optimized-profile/trace.nsys-rep', 'synthetic trace placeholder');
    trace = synthetic_trace();
    trace.update(
        analyzer_sha256=suite.sha((suite.STUDY / 'analyze.py')),
        results_sha256=suite.sha((folder / 'optimized-profile/results.json')),
        sqlite_sha256=suite.sha((folder / 'optimized-profile/trace.sqlite'))
    );
    save('optimized-profile/verified.json', trace);
    log_hash = save('counters/o2-ncu.log', 'SYNTHETIC tool unavailable');
    save(
        'counters/o2-status.json',
        {'status': 'unavailable', 'error': 'tool_not_found', 'log_sha256': log_hash}
    );
    save(
        'optimized-address-analysis.json',
        {
            'source_sha256': suite.sha((suite.STUDY / 'address_analysis.py')),
            'input_sha256': suite.sha((folder / 'inputs/inputs.json')),
            'profile_results_sha256': suite.sha(
                (folder / 'optimized-profile/results.json')
            )
        }
    );
    stages = [];
    for (name, _) in suite.steps(folder)[:-1] {
        digest = save(f'logs/{name}.log', 'SYNTHETIC: no commands executed');
        stages.append(
            {
                'name': name,
                'status': 'complete',
                'exit_code': 0,
                'log': f'logs/{name}.log',
                'log_sha256': digest
            }
        );
    }
    save(
        'commands.json',
        {
            'status': 'running',
            'started_utc': '2026-10-30T12:00:00+00:00',
            'source_sha256': {
                'scripts/gpu_walker/layout_bench/results.jac': suite.sha(
                    Path(evidence.__file__)
                )
            },
            'stages': stages
        }
    );
}

test "plan cannot execute or create outputs" {
    with tempfile.TemporaryDirectory() as temp {
        output = Path(temp) / 'directory with spaces';
        with patch.object(
            suite, 'run_suite', side_effect=AssertionError('execution forbidden')
        ), patch.object(
            subprocess, 'run', side_effect=AssertionError('subprocess forbidden')
        ), patch.object(
            subprocess,
            'check_output',
            side_effect=AssertionError('subprocess forbidden')
        ), contextlib.redirect_stdout(io.StringIO()) as stdout {
            suite.main(['plan', '--output', str(output)]);
        }
        check.assertFalse(output.exists());
        check.assertIn('PLAN ONLY', stdout.getvalue());
        check.assertIn('validate-gpu-statuses', stdout.getvalue());
    }
}

test "validation precedes timing and paths are arguments" {
    plan = suite.steps('/tmp/path with spaces', nvcc='/tool path/nvcc');
    names = [name for (name, _) in plan];
    check.assertLess(names.index('validate-gpu-statuses'), names.index('profile'));
    check.assertIn('--fresh-validation', `dict(plan)['compile-checked-o2']);
    check.assertIn('/tool path/nvcc', `dict(plan)['profile']);
    check.assertIn('--status-evidence', `dict(plan)['ordinary-events']);
    report_command = `dict(plan)['report'];
    check.assertEqual(
        report_command[2:7], ['-m', 'jaclang', 'run', '--backend', 'python']
    );
    check.assertTrue(report_command[7].endswith('/results.jac'));
    check.assertEqual(`dict(plan)['prepare-production'][-5:], `list(suite.SHAPES));
}

test "optimized python is rejected without work" {
    with patch.dict(os.environ, {'PYTHONOPTIMIZE': '1'}) {
        with check.assertRaisesRegex(ValueError, 'assertions') {
            suite.run_suite(None);
        }
    }
}

test "existing output is never overwritten" {
    with tempfile.TemporaryDirectory() as temp {
        args = `type('Args', (), {'output': Path(temp)})();
        with patch.dict(os.environ, {}, clear=True) {
            with check.assertRaisesRegex(ValueError, 'overwrite') {
                suite.run_suite(args);
            }
        }
    }
}

test "compiler from another installation is rejected before work" {
    with tempfile.TemporaryDirectory() as temp {
        args = types.SimpleNamespace(output=Path(temp) / 'uncreated');
        with patch.dict(os.environ, {}, clear=True), patch.object(
            suite.jaclang, '__file__', str(Path(temp) / 'installed/jaclang/__init__.py')
        ), patch.object(
            subprocess, 'run', side_effect=AssertionError('subprocess forbidden')
        ), patch.object(
            subprocess,
            'check_output',
            side_effect=AssertionError('subprocess forbidden')
        ) {
            with check.assertRaisesRegex(ValueError, 'requires this checkout') {
                suite.run_suite(args);
            }
        }
        check.assertFalse(args.output.exists());
    }
}

test "status validation failure prevents profile" {
    with tempfile.TemporaryDirectory() as temp {
        args = `type(
            'Args',
            (),
            `dict(
                output=(Path(temp) / 'run'),
                nvcc='nvcc',
                ptxas='ptxas',
                nsys='nsys',
                ncu='ncu'
            )
        )();
        calls = [];
        def fake_run(command: any, **kwargs: any) -> any {
            calls.append(command);
            return subprocess.CompletedProcess(
                command, 1 if ('validate_codegen.py' in ' '.join(command)) else 0
            );
        }
        with patch.dict(os.environ, {}, clear=True), patch.object(
            suite.sys, 'platform', 'linux'
        ), patch.object(suite.importlib.util, 'find_spec', return_value=object()), patch.object(
            suite.shutil, 'which', side_effect=lambda (x: any) { x; }
        ), patch.object(suite, 'source_hashes', return_value={}), patch.object(
            subprocess, 'check_output', return_value='synthetic'
        ), patch.object(subprocess, 'run', side_effect=fake_run), contextlib.redirect_stdout(
            io.StringIO()
        ) {
            with check.assertRaisesRegex(
                RuntimeError, 'validate-gpu-statuses failed'
            ) {
                suite.run_suite(args);
            }
        }
        check.assertEqual(len(calls), 4);
        result = evidence.read((args.output / 'commands.json'));
        check.assertEqual(result['status'], 'failed');
        check.assertNotIn('profile', [s['name'] for s in result['stages']]);
    }
}

test "complete run and ratio direction" {
    evidence.validate_run(synthetic_run(), warmup=3, repeats=15);
    evidence.validate_trace(synthetic_trace(), synthetic_run());
    rows = evidence.primary_rows(synthetic_trace());
    check.assertEqual(len(rows), 5);
    check.assertEqual(rows[0]['layout_speedup'], 2.0);
    check.assertEqual(rows[0]['residual_gap'], 5.0);
}

test "incomplete wrong geometry and unchecked replays rejected" {
    for mutate in [
        lambda (r: any) { r.update(complete=False); },
        lambda (r: any) { r['cases'][0]['arms'][evidence.AFTER].update(
            block=[64, 1, 1]
        ); },
        lambda (r: any) { r['records'][0].update(
            all_outputs_and_statuses_checked=False
        ); },
        lambda (r: any) { r['records'].pop(); },
        lambda (r: any) { r['records'].append(copy.deepcopy(r['records'][0])); },
        lambda (r: any) { r['records'][0].update(event_us=float('nan')); },
        lambda (r: any) { r['cases'][0].update(lanes=1); },
        lambda (r: any) { r['cases'][0]['arms'][evidence.BEFORE].update(
            median_event_us=42.0
        ); }
    ] {
        with check.subTest(mutation=mutate) {
            run = synthetic_run();
            mutate(run);
            with check.assertRaises(ValueError) {
                evidence.validate_run(run, warmup=3, repeats=15);
            }
        }
    }
}

test "trace rounds and all reported distributions match raw launches" {
    for mutate in [
        lambda (d: any) { d['summaries'][0].update(pair_mean_us=([999999.0] * 15)); },
        lambda (d: any) { d['summaries'][0].update(p10_us=42.0); },
        lambda (d: any) { d['summaries'][0].update(median_pair_mean_us=42.0); },
        lambda (d: any) { d['samples'][53].update(pair=1); },
        lambda (d: any) { d['samples'][53].update(graph_node=15); },
        lambda (d: any) { d['samples'][53].update(launch_index=0); },
        lambda (d: any) { d['samples'][53].update(kernel_us=-1.0); },
        lambda (d: any) { d['samples'][53].update(kernel='wrong_kernel'); },
        lambda (d: any) { d['samples'][53].update(end_ns=0); },
        lambda (d: any) { d['samples'].pop(); }
    ] {
        trace = synthetic_trace();
        mutate(trace);
        with check.assertRaises(ValueError) {
            evidence.validate_trace(trace, synthetic_run());
        }
    }
}

test "missing duplicate or invalid trace summary rejected" {
    for mutate in [
        lambda (d: any) { d['summaries'].pop(); },
        lambda (d: any) { d['summaries'].append(copy.deepcopy(d['summaries'][0])); },
        lambda (d: any) { d['summaries'][0].update(median_us=0); },
        lambda (d: any) { d['summaries'][0].update(pair_mean_us=([0] * 15)); }
    ] {
        trace = synthetic_trace();
        mutate(trace);
        with check.assertRaises(ValueError) {
            evidence.primary_rows(trace);
        }
    }
}

test "reports derive conclusions and do not reuse old numbers" {
    with tempfile.TemporaryDirectory() as temp {
        folder = Path(temp);
        fixture(folder);
        with patch.object(
            evidence,
            'write_pdf',
            side_effect=lambda (
                path: any, _rows: any, _gpu: any, _ptx_hash: any, _run: any
            ) { path.write_bytes(b'SYNTHETIC PDF PLACEHOLDER'); }
        ) {
            evidence.build(folder);
        }
        check.assertEqual(
            evidence.read((folder / 'contract-validation.json'))['status'], 'PASS'
        );
        check.assertIn(
            'improves 5 cases and regresses in 0', (folder / 'REPORT.md').read_text()
        );
        check.assertEqual(
            evidence.read((folder / 'comparison.json'))['rows'][0]['layout_speedup'],
            2.0
        );
        check.assertNotIn('1.753', (folder / 'REPORT.md').read_text());
        provenance = evidence.read((folder / 'comparison.json'))['run'];
        check.assertEqual(provenance['run_id'], folder.name);
        check.assertEqual(provenance['started_utc'], '2026-10-30T12:00:00+00:00');
        check.assertEqual(
            provenance['primary_trace_sha256'],
            suite.sha(folder / 'optimized-profile/trace.sqlite')
        );
        check.assertIn(
            provenance['primary_trace_sha256'], (folder / 'REPORT.md').read_text()
        );
    }
}

test "synthetic PDF renders with installed matplotlib" {
    if (suite.importlib.util.find_spec('matplotlib') is None) {
        raise unittest.SkipTest('Matplotlib is optional for CPU-only harness tests');
    }
    with tempfile.TemporaryDirectory() as temp {
        path = Path(temp) / 'SYNTHETIC.pdf';
        evidence.write_pdf(
            path,
            evidence.primary_rows(synthetic_trace()),
            'SYNTHETIC UNIT TEST',
            'a' * 64,
            {
                'run_id': 'SYNTHETIC-PDF-TEST',
                'started_utc': '2026-10-30T12:00:00+00:00',
                'primary_trace_sha256': 'b' * 64
            }
        );
        check.assertTrue(path.read_bytes().startswith(b'%PDF-'));
    }
}

test "hash mismatch blocks publication" {
    with tempfile.TemporaryDirectory() as temp {
        folder = Path(temp);
        fixture(folder);
        (folder / 'optimized-codegen/O2.ptx').write_text('tampered');
        with check.assertRaisesRegex(ValueError, 'Hash mismatch') {
            evidence.build(folder);
        }
        check.assertFalse((folder / 'comparison.json').exists());
    }
}

test "regression ratio is retained" {
    trace = synthetic_trace();
    for s in trace['summaries'] {
        if (s['arm'] == evidence.BEFORE) {
            s.update(
                median_us=25.0,
                min_us=25.0,
                max_us=25.0,
                p10_us=25.0,
                p90_us=25.0,
                pair_mean_us=([25.0] * 15)
            );
        }
    }
    check.assertEqual(evidence.primary_rows(trace)[0]['layout_speedup'], 0.5);
}

def invoke_probe(
    folder: any, *, available: any, message: any = '', exit_code: any = 1
) -> any {
    prepare = types.ModuleType('prepare');
    (prepare.HERE, prepare.read) = (suite.STUDY, evidence.read);
    (prepare.write, prepare.sha) = (suite.write_json, suite.sha);
    def fake_process(command: any, **kwargs: any) -> any {
        runner = command.index(str(suite.STUDY / 'run.py'));
        check.assertEqual(command[runner - 2:runner], [sys.executable, '-B']);
        kwargs['stdout'].write(message);
        return subprocess.CompletedProcess(command, exit_code);
    }
    with patch.dict(sys.modules, {'prepare': prepare}), patch.object(
        sys, 'argv', ['counter_probe.py', str(folder), '--ncu', 'synthetic-ncu']
    ), patch.object(
        suite.shutil, 'which', return_value='synthetic-ncu' if available else None
    ), patch.object(subprocess, 'run', side_effect=fake_process) as process {
        namespace = runpy.run_path(str((suite.STUDY / 'counter_probe.py')));
        namespace['main']();
        return process.call_count;
    }
}

test "missing profiler records unavailable without launch" {
    with tempfile.TemporaryDirectory() as temp {
        folder = Path(temp);
        check.assertEqual(invoke_probe(folder, available=False), 0);
        check.assertEqual(
            evidence.read((folder / 'counters/o2-status.json'))['error'],
            'tool_not_found'
        );
    }
}

test "denied counters do not require a completed probe" {
    with tempfile.TemporaryDirectory() as temp {
        folder = Path(temp);
        invoke_probe(folder, available=True, message='ERR_NVGPUCTRPERM');
        check.assertEqual(
            evidence.read((folder / 'counters/o2-status.json'))['status'], 'unavailable'
        );
        check.assertFalse((folder / 'counters/o2-probe/results.json').exists());
    }
}

test "unexpected profiler failure is not silently accepted" {
    with tempfile.TemporaryDirectory() as temp {
        folder = Path(temp);
        with check.assertRaises(AssertionError) {
            invoke_probe(folder, available=True, message='unexpected profiler failure');
        }
        check.assertEqual(
            evidence.read((folder / 'counters/o2-status.json'))['status'], 'failed'
        );
    }
}
