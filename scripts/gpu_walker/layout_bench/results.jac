"""Validate a fresh layout experiment and explain its measured results."""
import argparse;
import csv;
import json;
import math;
import from pathlib { Path }
import statistics;
import from scripts.gpu_walker.layout_bench.benchmark {
    HERE,
    ROOT,
    STUDY,
    MATMUL,
    SHAPES,
    sha,
    write_json
}

glob BEFORE: any = 'Jac before (Random928 + checked LLVM O2)',
     AFTER: any = 'Jac after (Predicted + checked LLVM O2)',
     REFERENCE: any = 'Handwritten CUDA reference (nvcc O3)',
     PRIMARY: any = [BEFORE, AFTER, REFERENCE],
     ARMS: any = PRIMARY + ['Random929 robustness', 'Random930 robustness'],
     CASES: any = {
         ('matmul-' + shape): `list(map(int, shape.split('x'))) for shape in SHAPES
     },
     STATUS_CASES: any = {
         'valid',
         'multiply_overflow',
         'add_overflow',
         'round_limit_cycle',
         'queue_capacity_branch',
         'invalid_negative_head',
         'invalid_large_head',
         'invalid_edge_target',
         'invalid_negative_csr',
         'invalid_csr_end',
         'seed_queue_capacity',
         'type_mismatch_skips_visit',
         'empty_channel'
     };

def require(condition: any, message: any) -> any {
    if not condition {
        raise ValueError(message);
    }
}

def read(path: any) -> any {
    return json.loads(Path(path).read_text());
}

def check_hash(path: any, expected: any) -> any {
    require((sha(path) == expected), f'Hash mismatch: {path}');
}

def validate_run(run: any, *, warmup: any, repeats: any) -> any {
    require((run.get('complete') is True), 'Incomplete measurement run');
    require((run['primary_arms'] == PRIMARY), 'Incorrect primary arms');
    require(
        (
            (run['warmup'], run['repeats'], run['inner'], run['order_seed'])
            == (warmup, repeats, 16, 237)
        ),
        'Measurement protocol changed'
    );
    require(
        (run['jac_function_loaded_once_for_all_layouts'] is True),
        'Jac arms must share one compiled function'
    );
    require(
        (run['jac_compilation_policy'] == 'checked standard LLVM O2'),
        'Unchecked or incorrect Jac compiler policy'
    );
    require(
        (run['reference_kernel'] == 'matmul_tiled_i64'), 'Incorrect CUDA reference'
    );
    require(
        (
            ('-O3' in run['nvcc_command'])
            and ('-arch=compute_86' in run['nvcc_command'])
        ),
        'Incorrect CUDA compiler policy'
    );
    require(
        (
            (len(run['cases']) == len(CASES))
            and ({c['id'] for c in run['cases']} == `set(CASES))
        ),
        'Missing or duplicate workload'
    );
    for `case in run['cases'] {
        (m, _, n) = CASES[`case['id']];
        require(
            ((`case['shape'] == CASES[`case['id']]) and (`case['lanes'] == (m * n))),
            'Incorrect shape or partial output coverage'
        );
        require(
            (
                (`case['all_outputs_and_statuses_verified'] is True)
                and (
                    `case['all_node_permutations_and_logical_traversals_verified']
                    is True
                )
            ),
            'Correctness audit failed'
        );
        require((`set(`case['arms']) == `set(ARMS)), 'Missing or unexpected arm');
        for (arm, data) in `case['arms'].items() {
            grid = [((n + 15) // 16), ((m + 15) // 16), 1]
                if (arm == REFERENCE)
                else [(((m * n) + 127) // 128), 1, 1];
            block = [16, 16, 1] if (arm == REFERENCE) else [128, 1, 1];
            kernel = 'matmul_tiled_i64'
                if (arm == REFERENCE)
                else 'jac_Dot_cursors_batch';
            require(
                (
                    (data['grid'] == grid)
                    and (data['block'] == block)
                    and (data['kernel'] == kernel)
                ),
                'Kernel or launch geometry changed'
            );
            require((data['sample_n'] == repeats), 'Incorrect event sample count');
        }
    }
    expected = {
        (cid, arm, phase, pair) for cid in CASES for arm in ARMS
        for (phase, count) in [('warmup', warmup), ('measured', repeats)]
        for pair in range(count)
    };
    actual = `set();
    for record in run['records'] {
        key = (record['case'], record['arm'], record['phase'], record['pair']);
        require((key not in actual), 'Duplicate replay record');
        actual.add(key);
        require(
            (record['all_outputs_and_statuses_checked'] is True), 'Unchecked replay'
        );
        require(
            (math.isfinite(record['event_us']) and (record['event_us'] > 0)),
            'Invalid event duration'
        );
    }
    require((actual == expected), 'Missing or unexpected replay records');
    for `case in run['cases'] {
        for (arm, data) in `case['arms'].items() {
            values = [
                r['event_us']
                for r in run['records']
                if (
                    (r['case'] == `case['id'])
                    and (r['arm'] == arm)
                    and (r['phase'] == 'measured')
                )
            ];
            require(
                (
                    (data['median_event_us'] == statistics.median(values))
                    and (data['min_event_us'] == min(values))
                    and (data['max_event_us'] == max(values))
                ),
                'Event summary does not match replay records'
            );
        }
    }
}

def validate_trace(verified: any, run: any) {
    expected = [];
    kernels = {};
    for `case in run['cases'] {
        for (arm, data) in `case['arms'].items() {
            kernels[(`case['id'], arm)] = data['kernel'];
            expected.append((`case['id'], arm, 'prime', -1, 0));
        }
        for record in run['records'] {
            if (record['case'] == `case['id']) {
                expected.extend(
                    (
                        record['case'],
                        record['arm'],
                        record['phase'],
                        record['pair'],
                        node_index
                    ) for node_index in range(run['inner'])
                );
            }
        }
    }
    require(
        (
            (
                verified['launches_verified']
                == len(verified['samples'])
                == len(expected)
                == 7225
            )
            and (verified['measured_launches'] == 6000)
        ),
        'Incomplete kernel trace'
    );
    measured = {};
    previous_start = -1;
    for (index, identity) in enumerate(expected) {
        sample: any = verified['samples'][index];
        require(
            (
                (sample['launch_index'] == index)
                and (
                    (
                        sample['case'],
                        sample['arm'],
                        sample['phase'],
                        sample['pair'],
                        sample['graph_node']
                    )
                    == identity
                )
                and (sample['kernel'] == kernels[(sample['case'], sample['arm'])])
            ),
            'Trace launch identity or round coverage changed'
        );
        require(
            (
                math.isfinite(sample['kernel_us'])
                and (sample['kernel_us'] > 0)
                and (sample['start_ns'] >= previous_start)
                and (sample['end_ns'] > sample['start_ns'])
                and (
                    sample['kernel_us']
                    == ((sample['end_ns'] - sample['start_ns']) / 1000)
                )
            ),
            'Invalid raw kernel duration'
        );
        previous_start = sample['start_ns'];
        if (sample['phase'] == 'measured') {
            key = (sample['case'], sample['arm']);
            measured.setdefault(key, []).append(sample);
        }
    }
    for summary in verified['summaries'] {
        samples = measured[(summary['case'], summary['arm'])];
        values = sorted(s['kernel_us'] for s in samples);
        pair_means = [
            statistics.mean(
                s['kernel_us']
                for s in samples
                if (s['pair'] == pair)
            ) for pair in range(run['repeats'])
        ];
        calculated = {
            'sample_n': len(values),
            'median_us': statistics.median(values),
            'min_us': values[0],
            'max_us': values[-1],
            'p10_us': values[int(0.1 * (len(values) - 1))],
            'p90_us': values[int(0.9 * (len(values) - 1))],
            'pair_mean_us': pair_means,
            'median_pair_mean_us': statistics.median(pair_means)
        };
        require(
            all((summary[key] == value) for (key, value) in calculated.items()),
            'Trace summary does not match samples'
        );
    }
}

def primary_rows(verified: any) -> any {
    require((verified['status'] == 'PASS'), 'Trace audit did not pass');
    lookup = {};
    for summary in verified['summaries'] {
        key = (summary['case'], summary['arm']);
        require((key not in lookup), 'Duplicate trace summary');
        require(
            ((summary['sample_n'] == 240) and (len(summary['pair_mean_us']) == 15)),
            'Incorrect traced sample count'
        );
        for field in ['median_us', 'min_us', 'max_us', 'p10_us', 'p90_us'] {
            require(
                (math.isfinite(summary[field]) and (summary[field] > 0)),
                'Invalid kernel duration'
            );
        }
        require(
            all((math.isfinite(x) and (x > 0)) for x in summary['pair_mean_us']),
            'Invalid round duration'
        );
        require(
            (
                summary['min_us']
                <= summary['p10_us']
                <= summary['median_us']
                <= summary['p90_us']
                <= summary['max_us']
            ),
            'Invalid timing distribution'
        );
        lookup[key] = summary;
    }
    require(
        (`set(lookup) == {(cid, arm) for cid in CASES for arm in ARMS}),
        'Missing or unexpected trace summary'
    );
    rows = [];
    for (cid, shape) in CASES.items() {
        (before, after, ref) = [lookup[(cid, arm)]['median_us'] for arm in PRIMARY];
        rows.append(
            `dict(
                `case=cid,
                M=shape[0],
                K=shape[1],
                N=shape[2],
                jac_before_us=before,
                jac_after_us=after,
                cuda_reference_us=ref,
                layout_speedup=(before / after),
                residual_gap=(after / ref)
            )
        );
    }
    return rows;
}

def write_pdf(path: any, rows: any, gpu: any, ptx_hash: any, provenance: any) -> any {
    import matplotlib;
    matplotlib.use('Agg');
    import matplotlib.pyplot as plt;
    import from matplotlib.backends.backend_pdf { PdfPages }
    plt.rcParams['font.family'] = 'DejaVu Sans';
    with PdfPages(path) as pdf_context {
        pdf: any = pdf_context;
        fig: any = plt.figure(figsize=(11.7, 8.3), facecolor='white');
        fig.text(0.06, 0.92, 'Jac GPU layout benchmark', fontsize=22);
        fig.text(
            0.06,
            0.87,
            f'Device: {gpu} | Actual Nsight kernel medians, microseconds',
            fontsize=11
        );
        fig.text(
            0.06,
            0.83,
            f"Run: {provenance['run_id']} | Started UTC: {provenance['started_utc']}",
            fontsize=9
        );
        ax: any = fig.add_axes([0.06, 0.4, 0.88, 0.39]);
        ax.axis('off');
        data = [
            [
                ' x '.join(str(row[k]) for k in ['M', 'K', 'N']),
                *[
                    f'{row[k]:.3f}'
                    for k in ['jac_before_us', 'jac_after_us', 'cuda_reference_us']
                ],
                f"{row['layout_speedup']:.3f}x",
                f"{row['residual_gap']:.3f}x"
            ] for row in rows
        ];
        table: any = ax.table(
            cellText=data,
            colLabels=[
                'M x K x N',
                'Jac before\nRandom + O2',
                'Jac after\nPredicted + O2',
                'CUDA reference\nO3',
                'Before/after',
                'After/CUDA'
            ],
            loc='center'
        );
        table.auto_set_font_size(False);
        table.set_fontsize(10);
        table.scale(1, 2);
        notes = [
            'Both Jac layouts use identical checked PTX; only physical node placement changes.',
            'Before/after > 1: improvement. < 1: regression. No minimum speedup is assumed.',
            'After/CUDA measures the whole implementation gap, including representation and algorithm.',
            'Full output and status checks; 15 measured rounds x 16 nodes after 3 warmup rounds.',
            'Packing, transfers, compilation and verification are outside kernel timing.',
            'See REPORT.md, variability.json, raw samples and device snapshots for limits.',
            f'Checked O2 PTX SHA-256: {ptx_hash}',
            f"Primary trace SHA-256: {provenance['primary_trace_sha256']}"
        ];
        for (index, line) in enumerate(notes) {
            fig.text(
                0.06, (0.34 - (index * 0.035)), line, fontsize=9 if (index < 6) else 7
            );
        }
        pdf.savefig(fig);
        plt.close(fig.number);
    }
}

def build(folder: any) -> any {
    folder = Path(folder).resolve();
    record = read((folder / 'commands.json'));
    require(
        (record['status'] in ['running', 'complete']),
        'Experiment failed or is incomplete'
    );
    expected_stages = [
        'prepare-production',
        'audit-layouts',
        'compile-checked-o2',
        'validate-gpu-statuses',
        'profile',
        'export-trace',
        'audit-trace',
        'ordinary-events',
        'address-model',
        'counter-probe'
    ];
    require(
        ([s['name'] for s in record['stages'][:10]] == expected_stages),
        'Required experiment stages missing'
    );
    require(
        all(
            ((s['status'] == 'complete') and (s['exit_code'] == 0))
            for s in record['stages'][:10]
        ),
        'Required stage failed'
    );
    for stage in record['stages'][:10] {
        check_hash((folder / stage['log']), stage['log_sha256']);
    }
    for (name, digest) in record['source_sha256'].items() {
        check_hash((ROOT / name), digest);
    }
    inputs = read((folder / 'inputs/inputs.json'));
    cg = read((folder / 'optimized-codegen/codegen.json'));
    status = read((folder / 'optimized-codegen/status-validation.json'));
    profile = read((folder / 'optimized-profile/results.json'));
    ordinary = read((folder / 'optimized-ordinary/results.json'));
    verified = read((folder / 'optimized-profile/verified.json'));
    counter = read((folder / 'counters/o2-status.json'));
    model = read((folder / 'optimized-address-analysis.json'));
    require(
        (
            Path(inputs['source_manifest']).resolve()
            == (folder / 'production-inputs/inputs.json')
        ),
        'Inputs must come from this fresh run'
    );
    check_hash(
        (folder / 'production-inputs/inputs.json'), inputs['source_manifest_sha256']
    );
    check_hash((STUDY / 'prepare.py'), inputs['generator_sha256']);
    check_hash(
        (ROOT / 'jac/examples/gpu/named_cursors.jac'), inputs['source_jac_sha256']
    );
    check_hash((folder / 'inputs/Dot.ptx'), inputs['ptx_sha256']);
    require(
        (cg['production_ptx_sha256'] == inputs['ptx_sha256']), 'Baseline PTX mismatch'
    );
    require(
        cg.get('validation_policy', '').startswith('fresh'),
        'Fresh compilation validation is required'
    );
    for (file, key) in [
        ('O2.ptx', 'optimized_ptx_sha256'),
        ('raw.ll', 'raw_ir_sha256'),
        ('O2.ll', 'optimized_ir_sha256')
    ] {
        check_hash((folder / 'optimized-codegen' / file), cg[key]);
    }
    check_hash((STUDY / 'emit_checked_o2.py'), cg['generator_sha256']);
    check_hash((MATMUL / 'validate_codegen.py'), status['validator_sha256']);
    require(
        ((status['status'] == 'PASS') and (status['gpu_launches_checked'] == 26)),
        'Fresh status validation failed'
    );
    require(
        (
            status['ptx_sha256']
            == {'baseline': inputs['ptx_sha256'], 'O2': cg['optimized_ptx_sha256']}
        ),
        'Wrong PTX status validation'
    );
    require(
        (
            (len(status['cases']) == 13)
            and ({c['case'] for c in status['cases']} == STATUS_CASES)
        ),
        'Missing status fixtures'
    );
    for `case in status['cases'] {
        for variant in ['baseline', 'O2'] {
            v = `case['variants'][variant];
            require(
                (
                    (v['pass'] is True)
                    and (v['status'] == `case['expected_status'])
                    and (v['results'] == `case['expected_results'])
                ),
                'Status fixture mismatch'
            );
        }
    }
    require(
        (
            (len(inputs['cases']) == 5)
            and ({c['id'] for c in inputs['cases']} == `set(CASES))
        ),
        'Input workloads changed'
    );
    for `case in inputs['cases'] {
        require((`case['shape'] == CASES[`case['id']]), 'Input dimensions changed');
        require(
            (
                (
                    {x['name'] for x in `case['layouts']}
                    == {'before', 'after', 'random929', 'random930'}
                )
                and (len(`case['layouts']) == 4)
            ),
            'Input layouts changed'
        );
        require(
            (
                len({x['queue_capacity'] for x in `case['layouts']})
                == len({x['max_visits'] for x in `case['layouts']})
                == 1
            ),
            'Layout bounds differ'
        );
        files = [`case['expected']];
        for layout in `case['layouts'] {
            require(
                (
                    (
                        layout['audit'][
                            'all_node_fields_edges_heads_and_queue_remap_verified'
                        ]
                        is True
                    )
                    and (
                        layout['audit']['all_lane_cursor_arrivals_logically_identical']
                        is True
                    )
                ),
                'Layout identity audit failed'
            );
            files.extend([layout['identity_order'], *layout['files']]);
        }
        for info in files {
            path = (folder / 'inputs' / `case['id'] / info['file']).resolve();
            require(
                path.is_relative_to((folder / 'inputs')),
                'Input artifact escapes the run directory'
            );
            check_hash(path, info['sha256']);
        }
    }
    for (run, directory, warmup, repeats) in [
        (profile, 'optimized-profile', 3, 15),
        (ordinary, 'optimized-ordinary', 5, 25)
    ] {
        validate_run(run, warmup=warmup, repeats=repeats);
        for (path, key) in [
            ((STUDY / 'run.py'), 'runner_sha256'),
            ((STUDY / 'prepare.py'), 'prepare_sha256'),
            ((MATMUL / 'benchmark.py'), 'driver_sha256'),
            ((STUDY / 'RESEARCH_CONTRACT.md'), 'contract_sha256'),
            ((folder / 'inputs/inputs.json'), 'input_manifest_sha256'),
            ((folder / 'optimized-codegen/codegen.json'), 'optimized_codegen_sha256'),
            (
                (folder / 'optimized-codegen/status-validation.json'),
                'status_evidence_sha256'
            ),
            ((folder / 'optimized-codegen/O2.ptx'), 'jac_ptx_sha256'),
            ((MATMUL / 'matmul.cu'), 'reference_source_sha256'),
            ((folder / directory / 'matmul.ptx'), 'reference_ptx_sha256')
        ] {
            check_hash(path, run[key]);
        }
    }
    require(
        (profile['reference_ptx_sha256'] == ordinary['reference_ptx_sha256']),
        'CUDA reference changed between runs'
    );
    check_hash((STUDY / 'analyze.py'), verified['analyzer_sha256']);
    check_hash((folder / 'optimized-profile/results.json'), verified['results_sha256']);
    check_hash((folder / 'optimized-profile/trace.sqlite'), verified['sqlite_sha256']);
    rows = primary_rows(verified);
    validate_trace(verified, profile);
    check_hash((folder / 'counters/o2-ncu.log'), counter['log_sha256']);
    require(
        (
            (counter['status'] == 'collected')
            or (
                (counter['status'] == 'unavailable')
                and (counter['error'] in ['ERR_NVGPUCTRPERM', 'tool_not_found'])
            )
        ),
        'Unexpected counter failure'
    );
    check_hash((STUDY / 'address_analysis.py'), model['source_sha256']);
    check_hash((folder / 'inputs/inputs.json'), model['input_sha256']);
    check_hash(
        (folder / 'optimized-profile/results.json'), model['profile_results_sha256']
    );
    sources = [
        'inputs/inputs.json',
        'production-inputs/inputs.json',
        'optimized-codegen/codegen.json',
        'optimized-codegen/status-validation.json',
        'optimized-codegen/O2.ptx',
        'optimized-profile/results.json',
        'optimized-profile/verified.json',
        'optimized-profile/trace.sqlite',
        'optimized-profile/trace.nsys-rep',
        'optimized-ordinary/results.json',
        'optimized-address-analysis.json',
        'counters/o2-status.json',
        'counters/o2-ncu.log'
    ];
    provenance = {
        'run_id': folder.name,
        'started_utc': record['started_utc'],
        'output_directory': str(folder),
        'primary_trace_sha256': verified['sqlite_sha256']
    };
    write_json(
        (folder / 'comparison.json'),
        {
            'primary_arms': PRIMARY,
            'metric': 'median actual Nsight kernel end-start',
            'unit': 'microseconds',
            'source_run': 'optimized-profile',
            'run': provenance,
            'rows': rows,
            'contract_sha256': sha((STUDY / 'RESEARCH_CONTRACT.md')),
            'report_source_sha256': sha(Path(__file__)),
            'sources_sha256': {name: sha((folder / name)) for name in sources}
        }
    );
    with (folder / 'comparison.csv').open('w', newline='') as stream {
        writer = csv.DictWriter(stream, fieldnames=[*rows[0], 'unit', 'source_run']);
        writer.writeheader();
        writer.writerows(
            {** row, 'unit': 'microseconds', 'source_run': 'optimized-profile'}
            for row in rows
        );
    }
    write_json(
        (folder / 'variability.json'),
        {
            'primary_trace_summaries': verified['summaries'],
            'ordinary_event_cases': ordinary['cases']
        }
    );
    seeds = [];
    lookup = {(s['case'], s['arm']): s for s in verified['summaries']};
    for cid in CASES {
        after = lookup[(cid, AFTER)];
        for (seed, arm) in [(928, BEFORE), (929, ARMS[3]), (930, ARMS[4])] {
            before = lookup[(cid, arm)];
            seeds.append(
                {
                    'case': cid,
                    'seed': seed,
                    'median_ratio': (before['median_us'] / after['median_us']),
                    'paired_round_mean_ratios': [
                        (a / b)
                        for (a, b) in zip(before['pair_mean_us'], after['pair_mean_us'])
                    ]
                }
            );
        }
    }
    write_json((folder / 'seed-robustness.json'), {'primary_seed': 928, 'rows': seeds});
    lines = [
        '# Jac GPU layout results',
        '',
        f"Run: `{provenance['run_id']}`. Started UTC: {provenance[
            'started_utc'
        ]}. Output: `{provenance['output_directory']}`.",
        f"Primary trace SHA-256: `{provenance['primary_trace_sha256']}`.",
        '',
        f"Device: {profile['gpu']}. Fresh checked O2 PTX: `{profile[
            'jac_ptx_sha256'
        ]}`.",
        '',
        'Both Jac arms share identical checked PTX. Only node layout changes. CUDA uses the fixed tiled int64 O3 reference.',
        '',
        '| M x K x N | Random + O2 (us) | Predicted + O2 (us) | CUDA O3 (us) | Before/after | After/CUDA |',
        '| --- | ---: | ---: | ---: | ---: | ---: |'
    ];
    for row in rows {
        lines.append(
            (
                '| '
                + ' x '.join(str(row[k]) for k in ['M', 'K', 'N'])
                + ' | '
                + ' | '.join(
                    f'{row[k]:.3f}'
                    for k in [
                        'jac_before_us',
                        'jac_after_us',
                        'cuda_reference_us',
                        'layout_speedup',
                        'residual_gap'
                    ]
                )
                + ' |'
            )
        );
    }
    improved = sum((r['layout_speedup'] > 1) for r in rows);
    regressed = sum((r['layout_speedup'] < 1) for r in rows);
    lines += [
        '',
        f'By the measured medians, layout improves {improved} cases and regresses in {regressed}; {(
            5 - improved - regressed
        )} are equal. These counts do not establish statistical significance.',
        '',
        'Before/after above 1 means lower latency after reordering. Below 1 means regression. After/CUDA is the remaining whole-implementation gap, not solely compiler overhead.',
        '',
        'All outputs and statuses passed each replay; all permutations and logical cursor paths were audited. Fresh baseline and O2 kernels passed 13 host-JIT differential status fixtures each.',
        '',
        'Primary timing uses 15 measured rounds x 16 traced nodes after 3 warmup rounds, randomized across all five arms. Nodes within a replay are correlated. See [distributions](variability.json) and [seed robustness](seed-robustness.json).',
        '',
        'Packing, compilation, allocation, transfers, poisoning and verification are outside kernel timing. Preparation costs are in production-inputs/inputs.json; upload/capture and copyback/validation diagnostics are in each results.json. No CPU speedup or public-runtime end-to-end latency is claimed.',
        '',
        'The ordinary event run is separate and includes graph scheduling gaps. Primary ratios never mix runs.',
        '',
        f"Counter probe: {counter['status']} ({(
            counter.get('error') or 'see raw counter output'
        )}). Address-segment counts are a logical model, not measured cache misses or memory transactions.",
        '',
        'Device sharing is recorded below; these timings describe that environment. No exclusive GPU assumption is made.',
        '',
        '```text',
        profile['gpu_before'].rstrip(),
        '```',
        '',
        '```text',
        profile['gpu_after'].rstrip(),
        '```',
        '',
        'Exact commands and tool versions: commands.json. Raw source hashes: comparison.json and commands.json. Historical timings are not pooled into this report.',
        ''
    ];
    (folder / 'REPORT.md').write_text('\n'.join(lines));
    write_pdf(
        (folder / 'REPORT.pdf'),
        rows,
        profile['gpu'],
        profile['jac_ptx_sha256'],
        provenance
    );
    write_json(
        (folder / 'contract-validation.json'),
        {
            'status': 'PASS',
            'run': provenance,
            'primary_arms': PRIMARY,
            'jac_variable': 'physical node layout only; identical checked O2 PTX',
            'fresh_status_fixtures_per_kernel': 13,
            'full_output_coverage': True,
            'launches_verified': 7225,
            'outputs_sha256': {
                name: sha((folder / name))
                for name in [
                    'comparison.json',
                    'comparison.csv',
                    'REPORT.md',
                    'REPORT.pdf'
                ]
            }
        }
    );
}

with entry:__main__ {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument('output', `type=Path);
    build(parser.parse_args().output);
}
