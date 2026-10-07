"""Validation, bounded benchmark and profiler orchestration; never a Jac forward.

Called from tensor_runner.jac with actual Jac build()/greedy() functions.
CUDA workloads only run when --device cuda:0 is explicitly selected.
"""
import argparse
import cProfile
import datetime
import json
import os
import platform
import random
import statistics
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Any

IMPORT_START = time.perf_counter()

# Bound CPU and Inductor resources before torch import.
os.environ.setdefault('OMP_NUM_THREADS', '1')
os.environ.setdefault('MKL_NUM_THREADS', '1')
os.environ.setdefault('TORCHINDUCTOR_COMPILE_THREADS', '1')
os.environ.setdefault('MAX_JOBS', '1')
os.environ.setdefault('TORCHINDUCTOR_CACHE_DIR', '/tmp/jac-transformer-inductor')

import torch
from tensor_baseline import Baseline, NAMES
import reference
IMPORT_MS = (time.perf_counter() - IMPORT_START) * 1000

CONFIGS = {
    'small': dict(dimension=8, heads=2, hidden=16, vocabulary=13, source_length=4, target_length=3),
    'medium': dict(dimension=256, heads=8, hidden=1024, vocabulary=1024,
                   source_length=128, target_length=96),
}


def sync(device):
    if str(device).startswith('cuda'):
        torch.cuda.synchronize(device)


def environment(device):
    info = dict(python=sys.version, platform=platform.platform(), torch=torch.__version__,
                cuda_runtime=torch.version.cuda, device=device, cpu=platform.processor(),
                threads=torch.get_num_threads(), tf32=False, pid=os.getpid(),
                compile_cache=os.environ['TORCHINDUCTOR_CACHE_DIR'],
                time_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    if device.startswith('cuda'):
        info['gpu'] = torch.cuda.get_device_name(device)
        info['gpu_memory_bytes'] = torch.cuda.get_device_properties(device).total_memory
        info['nvidia_smi'] = subprocess.run(
            ['nvidia-smi', '--query-gpu=name,driver_version,memory.used,utilization.gpu',
             '--format=csv,noheader'], capture_output=True, text=True).stdout.strip()
    return info


def assert_close(actual, expected, dtype='float64'):
    atol, rtol = (2e-11, 2e-10) if dtype == 'float64' else (3e-5, 3e-4)
    torch.testing.assert_close(actual, expected, atol=atol, rtol=rtol)
    if actual.dtype == torch.int64:
        return 0.0
    return float((actual - expected).abs().max().item())


def probabilities(p):
    assert bool(torch.isfinite(p).all()) and bool((p >= 0).all())
    torch.testing.assert_close(p.sum(-1), torch.ones_like(p.sum(-1)), atol=1e-12 if p.dtype == torch.float64 else 1e-6,
                               rtol=1e-12 if p.dtype == torch.float64 else 1e-6)


def compare_states(model, baseline, dtype):
    errors = {name: assert_close(model.modules[name].output, output, dtype)
              for name, output in zip(NAMES, baseline.last[:18])}
    for name, expected in zip(('enc_attn', 'dec_attn', 'cross_attn'), baseline.last[18:]):
        errors[name + '_map'] = assert_close(model.modules[name].diagnostics['attention'], expected, dtype)
    return max(errors.values()), errors


def make_inputs(config, device):
    vocab = config['vocabulary']
    source = [(3 + i) % vocab for i in range(config['source_length'] - 1)] + [2]
    labels = [(6 + i) % vocab for i in range(config['target_length'] - 1)] + [2]
    target = [1] + labels[:-1]
    return torch.tensor(source, device=device, dtype=torch.int64), torch.tensor(target, device=device, dtype=torch.int64)


def new_model(build, config):
    return build(**{k: config[k] for k in ('dimension', 'heads', 'hidden', 'vocabulary')})


def validate(build, greedy, device, directory):
    """Short functional checks only, no performance measurements."""
    config = CONFIGS['small']
    model = new_model(build, config)
    list_source, list_target = [3, 4, 5, 2], [1, 6, 7]
    list_run = model.forward(list_source, list_target)
    list_outputs = {name: node.output for name, node in model.modules.items()}
    list_params = model.parameter_snapshot()
    cpu = new_model(build, config).to('cpu', 'float64')
    source_cpu, target_cpu = make_inputs(config, 'cpu')
    cpu_run = cpu.forward(source_cpu, target_cpu)
    independent = reference.forward(list_params, list_source, list_target)
    cpu_errors = {}
    for name, n in cpu.modules.items():
        assert_close(n.output, torch.tensor(list_outputs[name], dtype=n.output.dtype))
        cpu_errors[name] = assert_close(n.output, torch.tensor(independent[name], dtype=n.output.dtype))
    model = new_model(build, config).to(device, 'float64')
    source, target = make_inputs(config, device)
    base = Baseline(model.parameter_snapshot(), config['heads'], source, target)
    run = model.forward(source, target)
    baseline = run.probabilities.clone()
    base()
    max_error, state_errors = compare_states(model, base, 'float64')
    for name, n in model.modules.items():
        assert_close(n.output.cpu(), cpu.modules[name].output)
        assert n.output.device == source.device
        for parameter in n.parameters().values():
            assert parameter.device == source.device and parameter.dtype == torch.float64
        assert set(n.inbox) == set(n.required)
    assert len(run.trace) == 18 and len(set(run.trace)) == 18 and len(run.deliveries) == 22
    assert model.modules['enc_norm1'].inbox['skip'] is model.modules['enc_pos'].output
    assert model.modules['cross_attn'].inbox['memory'] is model.modules['enc_norm2'].output
    probabilities(baseline)
    mask = model.modules['dec_attn'].diagnostics['attention']
    assert bool((mask.triu(1) == 0).all())
    assert_close(mask.sum(-1), torch.ones_like(mask.sum(-1)))
    changed = model.forward(source, torch.tensor([1, 6, 10], dtype=torch.int64, device=device))
    assert_close(changed.probabilities[:2], baseline[:2])
    assert float((changed.probabilities[2] - baseline[2]).abs().max()) > 1e-6
    influence_run = model.forward(torch.tensor([8, 9, 10, 2], dtype=torch.int64, device=device), target)
    influence = float((influence_run.probabilities - baseline).abs().max())
    assert influence > 1e-6
    length_errors = []
    for src, tgt in (([8, 2], [1]), ([3], [1, 4, 5, 6, 7]), ([3, 4, 5, 6, 2], [1, 8])):
        s = torch.tensor(src, device=device, dtype=torch.int64)
        t = torch.tensor(tgt, device=device, dtype=torch.int64)
        model.forward(s, t)
        ref = Baseline(model.parameter_snapshot(), 2, s, t)
        ref()
        length_errors.append(compare_states(model, ref, 'float64')[0])
        probabilities(model.modules['probabilities'].output)
    repeat = model.forward(source, target)
    assert_close(repeat.probabilities, baseline)
    assert repeat.trace == run.trace and repeat.deliveries == run.deliveries
    assert_close(run.probabilities, baseline)
    ids = {name: {field: value.data_ptr() for field, value in n.parameters().items()}
           for name, n in model.modules.items()}
    model.forward(source, target)
    assert ids == {name: {field: value.data_ptr() for field, value in n.parameters().items()}
                   for name, n in model.modules.items()}
    # Dispatch audit: count CPU downloads, scalar extraction and synchronization
    # inside the resident-tensor graph forward only, not in validation assertions.
    from torch.utils._python_dispatch import TorchDispatchMode

    class ResidencyAudit(TorchDispatchMode):
        def __init__(self):
            super().__init__()
            self.bad = []
        def __torch_dispatch__(self, func, types, args=(), kwargs=None):
            kwargs = kwargs or {}
            if '_local_scalar_dense' in str(func):
                self.bad.append(str(func))
            if '_to_copy' in str(func) and str(kwargs.get('device', '')).startswith('cpu') and device.startswith('cuda'):
                self.bad.append(str(func))
            return func(*args, **kwargs)

    audit = ResidencyAudit()
    original_sync = torch.cuda.synchronize
    def forbidden_sync(*args, **kwargs):
        raise AssertionError('Per-forward CUDA synchronization is forbidden')
    torch.cuda.synchronize = forbidden_sync
    try:
        with audit:
            model.forward(source, target)
    finally:
        torch.cuda.synchronize = original_sync
    assert not audit.bad, audit.bad
    model.export_dot(str(directory / ('tensor_' + device.split(':')[0] + '.dot')))
    model.rewire_encoder_skip(True)
    rewired = model.forward(source, target)
    rewired_baseline = Baseline(model.parameter_snapshot(), 2, source, target, alternate=True)
    rewired_baseline()
    rewire_error = compare_states(model, rewired_baseline, 'float64')[0]
    delta = float((rewired.probabilities - baseline).abs().max())
    assert delta > 1e-6
    assert model.modules['enc_norm1'].inbox['skip'] is model.modules['enc_attn'].output
    model.export_dot(str(directory / ('tensor_' + device.split(':')[0] + '_rewired.dot')))
    model.rewire_encoder_skip(False)
    assert_close(model.forward(source, target).probabilities, baseline)
    model.remove_encoder_memory()
    try:
        model.forward(source, target)
    except AssertionError:
        pass
    else:
        raise AssertionError('Deleted real memory edge must block forward')
    assert not model.modules['cross_attn'].done and not model.modules['probabilities'].done
    mutated = new_model(build, config).to(device, 'float64')
    mutated.modules['enc_embed'].table[3, 0] += 0.4
    mutated.modules['dec_norm3'].gamma[0] = 1.7
    mutated.modules['dec_norm3'].beta[1] = 0.3
    mutated.modules['projection'].weight[0, 4] += 0.1
    mutated.modules['projection'].bias[4] = 0.2
    for name in ('enc_attn', 'dec_attn', 'cross_attn'):
        attn = mutated.modules[name]
        for field in ('w_q', 'w_k', 'w_v', 'w_o'):
            getattr(attn, field)[0, 0] += 0.1
        for field in ('b_q', 'b_k', 'b_v', 'b_o'):
            getattr(attn, field)[0] = 0.2
    ff = mutated.modules['dec_ffn']
    ff.w_up[0, 0] += 0.2
    ff.b_up[0] = 0.1
    ff.w_down[0, 0] += 0.3
    ff.b_down[1] = 0.2
    mutated.forward(source, target)
    mutation_base = Baseline(mutated.parameter_snapshot(), 2, source, target)
    mutation_base()
    mutation_error = compare_states(mutated, mutation_base, 'float64')[0]
    generated = greedy(new_model(build, config).to(device, 'float64'), list_source, steps=4)
    assert generated[0] == 1 and len(generated) <= 5
    # Confirm float32 separately after float64 correctness.
    fast = new_model(build, config).to(device, 'float32')
    fast.forward(source, target)
    fast_base = Baseline(fast.parameter_snapshot(), 2, source, target)
    fast_base()
    fast_error = compare_states(fast, fast_base, 'float32')[0]
    probabilities(fast.modules['probabilities'].output)
    return dict(status='passed', device=device, cpu_vs_independent_max_error=max(cpu_errors.values()),
                tensor_baseline_max_error=max_error, intermediate_errors=state_errors,
                length_errors=length_errors, encoder_influence=influence,
                rewire_error=rewire_error, rewire_probability_delta=delta,
                mutation_error=mutation_error, float32_error=fast_error, greedy=generated,
                resident_parameter_addresses_stable=True, resident_tensor_audit=audit.bad,
                trace=run.trace, deliveries=run.deliveries,
                cross_device_comparison='CPU vs CUDA' if device.startswith('cuda') else 'list vs CPU tensors',
                checks=['identical weights/inputs for list/CPU/requested device', 'all intermediates and attention maps',
                        'shapes/finite/probabilities', 'causal/future-token isolation',
                        'memory/residual identity', 'length/reset/old-return isolation',
                        'tensor residency/no per-node sync', 'actual graph rewire/restore/delete',
                        'named parameter mutation', 'greedy', 'float32'])


def distribution(values):
    ordered = sorted(values)
    def percentile(q):
        index = (len(ordered) - 1) * q
        lo = int(index)
        hi = min(lo + 1, len(ordered) - 1)
        return ordered[lo] + (ordered[hi] - ordered[lo]) * (index - lo)
    return dict(n=len(values), mean_ms=statistics.mean(values), median_ms=statistics.median(values),
                p10_ms=percentile(.1), p90_ms=percentile(.9), p95_ms=percentile(.95),
                min_ms=min(values), max_ms=max(values), raw_ms=values)


def validate_configuration(build, config, device, dtype, check_compile=False):
    """Validate bounded nontrivial shape and actual CPU/device differential."""
    model = new_model(build, config).to(device, dtype)
    source, target = make_inputs(config, device)
    run = model.forward(source, target)
    baseline = Baseline(model.parameter_snapshot(), config['heads'], source, target)
    baseline()
    error, errors = compare_states(model, baseline, dtype)
    cpu_model = new_model(build, config).to('cpu', dtype)
    cpu_model.forward(source.cpu(), target.cpu())
    cpu_device_errors = {name: assert_close(node.output.cpu(), cpu_model.modules[name].output, dtype)
                         for name, node in model.modules.items()}
    for name, node in model.modules.items():
        if name not in ('source', 'target'):
            length = config['source_length'] if name.startswith('enc_') else config['target_length']
            width = config['vocabulary'] if name in ('projection', 'probabilities') else config['dimension']
            assert node.output.shape == (length, width)
            assert bool(torch.isfinite(node.output).all())
    probabilities(run.probabilities)
    maps = model.modules['dec_attn'].diagnostics['attention']
    assert maps.shape == (config['heads'], len(target), len(target))
    assert bool((maps.triu(1) == 0).all())
    saved = run.probabilities.clone()
    assert_close(model.forward(source, target).probabilities, saved, dtype)
    model.rewire_encoder_skip(True)
    model.forward(source, target)
    changed_base = Baseline(model.parameter_snapshot(), config['heads'], source, target, True)
    changed_base()
    changed_error, _ = compare_states(model, changed_base, dtype)
    changed_delta = float((model.modules['probabilities'].output - saved).abs().max())
    assert changed_delta > 0
    compile_status = {}
    if check_compile:
        for alternate in (False, True):
            eager = Baseline(model.parameter_snapshot(), config['heads'], source, target, alternate)
            eager()
            compiled = Baseline(model.parameter_snapshot(), config['heads'], source, target, alternate)
            label = 'rewired' if alternate else 'original'
            try:
                compiled.compile()
                compiled()
            except Exception as exc:
                compile_status[label] = dict(status='unsupported_or_failed', error=repr(exc)[:4000])
            else:
                errs = [assert_close(a, b, dtype) for a, b in zip(compiled.last, eager.last)]
                compile_status[label] = dict(status='passed', max_error=max(errs))
    return dict(config=config, dtype=dtype, max_error=error, errors=errors,
                cpu_device_max_error=max(cpu_device_errors.values()),
                rewired_max_error=changed_error, rewired_probability_delta=changed_delta,
                compile=compile_status, status='passed')


def timed(fn, device):
    sync(device)
    begin = time.perf_counter_ns()
    output = fn()
    sync(device)
    return (time.perf_counter_ns() - begin) / 1e6, output


def measure(methods, device, warmup, samples, rounds):
    """Interleave method order per round, synchronizing only at request boundaries."""
    warm = {}
    values = {name: [] for name in methods}
    for name, fn in methods.items():
        start = time.perf_counter()
        for _ in range(warmup):
            fn()
        sync(device)
        warm[name] = (time.perf_counter() - start) * 1000
    rng = random.Random(1729)
    round_order = []
    for _ in range(rounds):
        order = list(methods)
        rng.shuffle(order)
        round_order.append(order)
        for name in order:
            for _ in range(samples):
                elapsed, _ = timed(methods[name], device)
                values[name].append(elapsed)
    result = {name: dict(end_to_end=distribution(v), warmup_total_ms=warm[name])
              for name, v in values.items()}
    if device.startswith('cuda'):
        for name, fn in methods.items():
            enqueues, spans = [], []
            start = torch.cuda.Event(enable_timing=True)
            end = torch.cuda.Event(enable_timing=True)
            start.record(); end.record(); end.synchronize()
            for _ in range(samples):
                sync(device)
                start.record()
                begin = time.perf_counter_ns()
                fn()
                enqueues.append((time.perf_counter_ns() - begin) / 1e6)
                end.record()
                end.synchronize()
                spans.append(start.elapsed_time(end))
            result[name]['host_enqueue'] = distribution(enqueues)
            result[name]['gpu_stream_span'] = distribution(spans)
    return dict(methods=result, round_order=round_order)


def profile_method(name, fn, device, directory, calls=3, jac_model=None):
    """Actual CPU call profile and Kineto trace, separate from timing samples."""
    sync(device)
    if jac_model is not None:
        jac_model.profile_nodes = False
    cpu = cProfile.Profile()
    cpu.enable()
    for _ in range(calls):
        fn()
    sync(device)
    cpu.disable()
    stats = []
    categories = defaultdict(float)
    import pstats
    for (file, line, func), (primitive, total, exclusive, inclusive, callers) in pstats.Stats(cpu).stats.items():
        stats.append(dict(file=file, line=line, function=func, calls=total,
                          exclusive_ms=exclusive * 1000, cumulative_ms=inclusive * 1000))
        if '/runtime/' in file or '/server/' in file or '/data/' in file:
            category = 'jac_runtime_server_data'
        elif file.endswith('model.jac'):
            category = 'jac_model_methods'
        elif 'torch' in file or 'torch' in func:
            category = 'torch_python_or_c_api'
        else:
            category = 'other'
        categories[category] += exclusive * 1000
    activities = [torch.profiler.ProfilerActivity.CPU]
    if device.startswith('cuda'):
        activities.append(torch.profiler.ProfilerActivity.CUDA)
    if jac_model is not None:
        jac_model.profile_nodes = True
    with torch.profiler.profile(activities=activities, record_shapes=True) as prof:
        for _ in range(calls):
            with torch.profiler.record_function('request/' + name):
                fn()
        sync(device)
    if jac_model is not None:
        jac_model.profile_nodes = False
    path = directory / (name + '.trace.json')
    prof.export_chrome_trace(str(path))
    events = json.loads(path.read_text())['traceEvents']
    kernels = [e for e in events if e.get('cat') == 'kernel' and 'dur' in e]
    if device.startswith('cuda') and not kernels:
        raise RuntimeError('CUDA profiler captured no kernels; cannot claim GPU profiling evidence')
    totals = defaultdict(lambda: [0, 0.0])
    for e in kernels:
        totals[e['name']][0] += 1
        totals[e['name']][1] += e['dur'] / 1000
    kernel_summary = sorted((dict(name=k, calls=v[0], duration_ms=v[1]) for k, v in totals.items()),
                            key=lambda v: v['duration_ms'], reverse=True)
    gpu_busy = sum(e['dur'] for e in kernels) / 1000
    window = (max(e['ts'] + e['dur'] for e in kernels) - min(e['ts'] for e in kernels)) / 1000 if kernels else None
    launches = [e for e in events if e.get('cat') == 'cuda_runtime' and 'LaunchKernel' in e.get('name', '')]
    node_ranges = [dict(name=e['name'], duration_ms=e.get('dur', 0) / 1000)
                   for e in events if e.get('name', '').startswith('Jac.node/')]
    return dict(calls=calls, trace_file=str(path), cprofile_node_ranges_enabled=False,
                kineto_node_ranges_enabled=jac_model is not None,
                cpu_exclusive_categories_ms=dict(categories),
                cpu_top=sorted(stats, key=lambda v: v['exclusive_ms'], reverse=True)[:30],
                cuda_kernel_count=len(kernels), kernel_sum_ms=gpu_busy,
                kernel_window_ms=window, kernel_window_minus_busy_ms=(window - gpu_busy) if window is not None else None,
                kernels=kernel_summary[:25], launch_count=len(launches),
                launch_cpu_ms=sum(e.get('dur', 0) for e in launches) / 1000,
                node_cpu_ranges=node_ranges)


def benchmark_case(build, config, config_name, device, dtype, directory, args):
    initialization = {}
    if device.startswith('cuda'):
        torch.cuda.reset_peak_memory_stats(device)
    start = time.perf_counter()
    model = new_model(build, config)
    initialization['jac_graph_and_seeded_list_parameters_ms'] = (time.perf_counter() - start) * 1000
    start = time.perf_counter()
    model.to(device, dtype)
    source, target = make_inputs(config, device)
    sync(device)
    initialization['parameter_and_input_placement_ms'] = (time.perf_counter() - start) * 1000
    model.record_trace = False
    first, run = timed(lambda: model.forward(source, target), device)
    initialization['jac_first_forward_including_position_mask_cache_ms'] = first
    original_probabilities = run.probabilities.clone()
    start = time.perf_counter()
    snapshot = model.parameter_snapshot()
    base = Baseline(snapshot, config['heads'], source, target)
    sync(device)
    initialization['baseline_snapshot_and_buffers_ms'] = (time.perf_counter() - start) * 1000
    first, expected = timed(base, device)
    initialization['eager_first_forward_ms'] = first
    assert_close(run.probabilities, expected, dtype)
    results = dict(config=config, config_name=config_name, dtype=dtype, device=device,
                   initialization=initialization, graphs={})
    for alternate in (False, True):
        graph_name = 'rewired' if alternate else 'original'
        model.rewire_encoder_skip(alternate)
        model.forward(source, target)
        eager = Baseline(snapshot, config['heads'], source, target, alternate)
        eager()
        state_error, _ = compare_states(model, eager, dtype)
        graph_probability_delta = float((model.modules['probabilities'].output - original_probabilities).abs().max())
        if alternate:
            assert graph_probability_delta > 0
        methods = {'jac_graph': lambda: model.forward(source, target).probabilities,
                   'torch_eager': eager}
        compile_info = {'status': 'disabled'}
        compiled = None
        if not args.no_compile:
            compiled = Baseline(snapshot, config['heads'], source, target, alternate)
            construction_start = time.perf_counter()
            try:
                compiled.compile()
                construction_ms = (time.perf_counter() - construction_start) * 1000
                first, output = timed(compiled, device)
                compile_error = assert_close(output, eager.last[17], dtype)
                for actual, expected in zip(compiled.last, eager.last):
                    assert_close(actual, expected, dtype)
                compile_info = dict(status='passed', backend='inductor', fullgraph=True, dynamic=False,
                                    cudagraphs=False, construction_ms=construction_ms,
                                    first_call_compile_and_execution_ms=first, max_probability_error=compile_error)
                methods['torch_compile'] = compiled
            except AssertionError:
                raise
            except Exception as exc:
                compile_info = dict(status='unsupported_or_failed', error=repr(exc)[:4000])
                print('torch.compile unavailable:', device, dtype, graph_name, compile_info['error'], flush=True)
        model.forward(source, target)
        result = measure(methods, device, args.warmup, args.samples, args.rounds)
        model.forward(source, target)
        replay = measure({'walker_handle_replay': lambda: model.schedule_replay(source, target)},
                         device, args.warmup, args.samples, args.rounds)
        result['scheduler_replay'] = replay['methods']['walker_handle_replay']
        result['compile'] = compile_info
        result['max_intermediate_error'] = state_error
        result['probability_delta_from_original_graph'] = graph_probability_delta
        model.forward(source, target)
        eager()
        compare_states(model, eager, dtype)
        probabilities(model.modules['probabilities'].output)
        result['profiles'] = {}
        profile_dir = directory / 'profiles'
        profile_dir.mkdir(exist_ok=True)
        for name, fn in methods.items():
            label = f'{config_name}_{device.split(":")[0]}_{dtype}_{graph_name}_{name}'
            result['profiles'][name] = profile_method(label, fn, device, profile_dir,
                                                      jac_model=model if name == 'jac_graph' else None)
        model.profile_nodes = False
        results['graphs'][graph_name] = result
        print(config_name, device, dtype, graph_name,
              {k: round(v['end_to_end']['median_ms'], 4) for k, v in result['methods'].items()}, flush=True)
    if device.startswith('cuda'):
        results['max_cuda_allocated_bytes'] = torch.cuda.max_memory_allocated(device)
        results['max_cuda_reserved_bytes'] = torch.cuda.max_memory_reserved(device)
    return results


def main(build: Any, greedy: Any, folder: str) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=('validate', 'benchmark'), default='validate')
    parser.add_argument('--device', default='cpu', choices=('cpu', 'cuda:0'))
    parser.add_argument('--output', default='results')
    parser.add_argument('--configs', nargs='+', choices=tuple(CONFIGS), default=['small', 'medium'])
    parser.add_argument('--dtypes', nargs='+', choices=('float64', 'float32'), default=['float64', 'float32'])
    parser.add_argument('--warmup', type=int, default=5)
    parser.add_argument('--samples', type=int, default=12)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--no-compile', action='store_true')
    parser.add_argument('--check-compile', action='store_true', help='Validate compiled outputs without a timing benchmark')
    parser.add_argument('--exclusive-note', default='')
    args = parser.parse_args([a for a in sys.argv[1:] if a != '--'])
    if args.mode == 'benchmark' and args.device.startswith('cuda') and not args.exclusive_note:
        parser.error('CUDA timing needs a coordinated exclusive slot recorded in --exclusive-note')
    if not 1 <= args.samples <= 100 or not 1 <= args.rounds <= 10 or not 1 <= args.warmup <= 50:
        parser.error('Resource limits: samples<=100, rounds<=10, warmup<=50; all positive')
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch._dynamo.config.recompile_limit = 32
    directory = Path(folder) / args.output
    directory.mkdir(parents=True, exist_ok=True)
    bootstrap = {'torch_baseline_reference_import_ms': IMPORT_MS,
                 'inductor_cache_preexisting': Path(os.environ['TORCHINDUCTOR_CACHE_DIR']).exists()}
    if args.device.startswith('cuda'):
        if not torch.cuda.is_available():
            raise RuntimeError('CUDA requested but unavailable; never silently substitute CPU')
        start = time.perf_counter()
        torch.cuda.init()
        sync(args.device)
        bootstrap['cuda_context_initialization_ms'] = (time.perf_counter() - start) * 1000
    report = dict(environment=environment(args.device), arguments=vars(args), bootstrap=bootstrap,
                  inference_only=True, measurement_notes=[
                      'Graph walker runs on host; PyTorch tensor math runs on CPU/CUDA.',
                      'Resident tokens/weights; no transfers or scalar reads inside module forwards.',
                      'E2E syncs only request boundaries; CUDA events include host-induced idle gaps.',
                      'Actual kernel durations and CPU categories come from separate profiler runs.',
                      'Handle replay is a scheduling-only microbenchmark, not Transformer inference.',
                      'Baselines retain all intermediate outputs/maps to match graph observability.',
                      'Trace collection disabled for timing, enabled separately for profiler.',
                      'No CUDA graphs, no TF32, one CPU thread, compile workers limited to one.'])
    with torch.inference_mode():
        if args.mode == 'validate':
            report['validation'] = validate(build, greedy, args.device, directory)
            report['configuration_validation'] = {
                name + '_' + dtype: validate_configuration(build, CONFIGS[name], args.device, dtype, args.check_compile)
                for name in args.configs for dtype in args.dtypes}
            filename = directory / ('validation_' + args.device.split(':')[0] + '.json')
        else:
            report['cases'] = []
            filename = directory / ('benchmark_' + args.device.split(':')[0] + '.json')
            for config_name in args.configs:
                for dtype in args.dtypes:
                    case = benchmark_case(build, CONFIGS[config_name], config_name, args.device, dtype, directory, args)
                    report['cases'].append(case)
                    filename.write_text(json.dumps(report, indent=2))
    report['completed_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    filename.write_text(json.dumps(report, indent=2))
    print('Saved', filename, flush=True)
    if args.mode == 'validate':
        print(json.dumps(report['validation'], indent=2), flush=True)
