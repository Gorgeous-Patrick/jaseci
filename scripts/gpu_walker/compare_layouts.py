"""Measure Ours versus Random with the actual Jac chain walker and CUDA runtime.

Requires this checkout's Jac environment and an NVIDIA GPU. --profile also needs
Nsight Systems. Saved packed inputs let profiling replay exactly the same data
without rebuilding the Jac graph. No handwritten GPU kernel or CPU fallback.
"""

import argparse
from array import array
from contextlib import contextmanager
import ctypes as c
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import random
import shutil
import sqlite3
import statistics
import subprocess
import sys
import time

from verify import reorder_nodes, same


def write_json(path, document):
    path.write_text(json.dumps(document, indent=2) + '\n')


def telemetry():
    query = 'name,driver_version,pstate,clocks.sm,clocks.mem,temperature.gpu,power.draw'
    return subprocess.check_output([
        'nvidia-smi', '--query-gpu=' + query, '--format=csv',
    ], text=True).strip()


@contextmanager
def memory_context():
    from jaclang.runtime.context import ExecutionContext
    from jaclang.runtime.runtime import JacRuntime

    base, target = JacRuntime.get_base_path_dir(), JacRuntime.get_full_target_path()
    try:
        JacRuntime.set_base_path(None)
        JacRuntime.set_full_target_path(None)
        context = ExecutionContext()
    finally:
        JacRuntime.set_base_path(base)
        JacRuntime.set_full_target_path(target)
    token = JacRuntime.push_request_context(context)
    try:
        yield
    finally:
        try:
            context.close()
        finally:
            JacRuntime.reset_request_context(token)


def save_buffers(directory, label, buffers):
    files = []
    for name, buf in zip(('values', 'links', 'heads', 'initial'), buffers.arrays()):
        path = directory / f'{label}.{name}.bin'
        data = buf.tobytes()
        path.write_bytes(data)
        files.append(dict(path=str(path), type=buf.typecode, count=len(buf),
                          sha256=hashlib.sha256(data).hexdigest()))
    return files


def load_buffers(files):
    from jaclang.runtime.gpu_memory import ChainBuffers

    arrays = []
    for info in files:
        data = Path(info['path']).read_bytes()
        if hashlib.sha256(data).hexdigest() != info['sha256']:
            raise ValueError('Packed input checksum mismatch')
        buf = array(info['type'])
        buf.frombytes(data)
        if len(buf) != info['count']:
            raise ValueError('Packed input length mismatch')
        arrays.append(buf)
    walkers = len(arrays[2])
    return ChainBuffers(*arrays, array('d', [0.0]) * walkers,
                        array('I', [0xffffffff]) * walkers)


def prepare_case(runtime, chain, count, length, seeds, output):
    """Use real Jac objects; the existing packer must produce Ours itself."""
    from jaclang.runtime.gpu_memory import chain_buffers
    from jaclang.runtime.runtime import JacRuntime

    directory = output / f'length-{length}'
    directory.mkdir()
    started = time.perf_counter()
    nodes = [chain.Cell(value=float(i + 1)) for i in range(count * length)]
    for base in range(0, len(nodes), length):
        for hop in range(length - 1):
            JacRuntime.connect(nodes[base + hop], nodes[base + hop + 1], chain.Next)
    walkers = [chain.ChainSum(total=float(i * 10)) for i in range(count)]
    starts = nodes[::length]
    graph_ms = (time.perf_counter() - started) * 1000
    expected = [float(i * 10 + length * (2 * i * length + length + 1) // 2)
                for i in range(count)]
    started = time.perf_counter()
    batch = runtime.prepare(walkers, starts)
    pack_ms = (time.perf_counter() - started) * 1000
    buffers = batch.buffers
    # This checks the order produced by the object packer, not a synthetic layout.
    assert list(buffers.heads) == list(range(count))
    for hop in range(length):
        for lane in range(count):
            slot = hop * count + lane
            assert buffers.values[slot] == float(lane * length + hop + 1)
            assert buffers.links[slot] == (slot + count if hop + 1 < length else -1)
    # Independent ordinary Jac execution for a bounded subset, including last lane.
    for lane in sorted({0, count // 2, count - 1}):
        walker = chain.ChainSum(total=float(lane * 10))
        JacRuntime.spawn(walker, starts[lane])
        same([walker.total], [expected[lane]])
    layouts = [dict(label='Ours', seed=None,
                    files=save_buffers(directory, 'ours', buffers))]
    for seed in seeds:
        started = time.perf_counter()
        order = list(range(len(nodes)))
        random.Random(seed).shuffle(order)
        values, links, heads = reorder_nodes(buffers.values, buffers.links,
                                           buffers.heads, order)
        shuffled = chain_buffers(values, links, heads, list(buffers.initial))
        shuffle_ms = (time.perf_counter() - started) * 1000
        layouts.append(dict(label='Random', seed=seed, shuffle_ms=shuffle_ms,
                            files=save_buffers(directory, f'random-{seed}', shuffled)))
    return dict(length=length, walkers=count, nodes=len(nodes), expected=expected,
                graph_build_ms=graph_ms, pack_ms=pack_ms, layouts=layouts,
                payload_bytes=batch.memory_plan().payload_bytes())


def sample_order(seed, warmup, repeats):
    """Alternate AB/BA within each paired comparison to balance temporal drift."""
    for phase, rounds in (('warmup', warmup), ('measured', repeats)):
        for pair in range(rounds):
            labels = ['Ours', 'Random'] if (pair + seed) % 2 else ['Random', 'Ours']
            for label in labels:
                yield phase, pair, label


def execute_cases(manifest, output, profiled=False):
    from jaclang.runtime.gpu_cuda import CudaSession

    records = []
    ptx = (output / 'chain.ptx').read_text()
    assert hashlib.sha256(ptx.encode()).hexdigest() == manifest['ptx_sha256']
    session = CudaSession(ptx, manifest['kernel'], manifest['device'],
                          manifest['block_size'])
    driver = session.driver
    before = telemetry()
    pushed = False
    capturing = False
    try:
        if profiled:
            # Explicit flush before context destruction is important for ctypes
            # clients; otherwise some Nsight versions export an empty CUDA trace.
            for name in ('cuProfilerStart', 'cuProfilerStop'):
                function = getattr(driver.library, name)
                function.argtypes, function.restype = [], c.c_int
            driver.call('cuCtxPushCurrent_v2', session.context)
            pushed = True
            driver.call('cuProfilerStart')
            capturing = True
        for case in manifest['cases']:
            ours = load_buffers(case['layouts'][0]['files'])
            for layout in case['layouts'][1:]:
                random_buffers = load_buffers(layout['files'])
                buffers_by_label = {'Ours': ours, 'Random': random_buffers}
                for phase, pair, label in sample_order(
                        layout['seed'], manifest['warmup'], manifest['repeats']):
                    buffers = buffers_by_label[label]
                    # Poison outputs outside the timer so missed execution fails.
                    buffers.results[:] = array('d', [float('nan')]) * case['walkers']
                    buffers.status[:] = array('I', [0xffffffff]) * case['walkers']
                    started = time.perf_counter_ns()
                    session.execute(buffers)
                    elapsed_us = (time.perf_counter_ns() - started) / 1000
                    same(buffers.results, case['expected'])
                    assert not any(buffers.status)
                    records.append(dict(length=case['length'], seed=layout['seed'],
                                        phase=phase, pair=pair, layout=label,
                                        execute_us=elapsed_us))
                print(f"{'Profile' if profiled else 'Wall'}: "
                      f"{case['walkers']} x {case['length']}, "
                      f"seed {layout['seed']}: all results PASS", flush=True)
        after = telemetry()
    finally:
        try:
            if capturing:
                driver.call('cuProfilerStop')
        finally:
            try:
                if pushed:
                    popped = c.c_void_p()
                    driver.call('cuCtxPopCurrent_v2', c.byref(popped))
            finally:
                session.close()
    result = dict(gpu=session.gpu_name, driver=session.driver_version,
                  telemetry_before=before, telemetry_after=after,
                  profiled=profiled, records=records)
    write_json(output / ('profile-launches.json' if profiled else 'wall.json'), result)
    return result


def attach_kernel_times(database, records, kernel, walkers, block_size):
    """Reject incomplete traces instead of silently matching the wrong launches."""
    with sqlite3.connect(database) as db:
        rows = db.execute('''
            SELECT k.end-k.start, s.value, k.gridX, k.gridY, k.gridZ,
                   k.blockX, k.blockY, k.blockZ
            FROM CUPTI_ACTIVITY_KIND_KERNEL k JOIN StringIds s ON k.shortName=s.id
            ORDER BY k.start
        ''').fetchall()
    if len(rows) != len(records):
        raise ValueError(f'Incomplete CUDA trace: {len(rows)} kernels, '
                         f'{len(records)} recorded launches')
    grid = (walkers + block_size - 1) // block_size
    for record, row in zip(records, rows):
        if row[1:] != (kernel, grid, 1, 1, block_size, 1, 1) or row[0] <= 0:
            raise ValueError(f'Unexpected kernel or launch geometry: {row}')
        record['kernel_us'] = row[0] / 1000


def distribution(values):
    values = sorted(values)
    return dict(samples=len(values), median=statistics.median(values),
                p10=values[int((len(values) - 1) * .1)],
                p90=values[int((len(values) - 1) * .9)])


def summarize(records, metric):
    summaries = []
    for length in sorted({r['length'] for r in records}):
        measured = [r for r in records if r['phase'] == 'measured' and
                    r['length'] == length]
        by_layout = {label: distribution([r[metric] for r in measured
                                         if r['layout'] == label])
                     for label in ('Ours', 'Random')}
        pairs = {}
        for record in measured:
            pairs.setdefault((record['seed'], record['pair']), {})[
                record['layout']] = record[metric]
        ratios = [p['Random'] / p['Ours'] for p in pairs.values()]
        summaries.append(dict(length=length, unit='us', **by_layout,
                              paired_random_over_ours=distribution(ratios)))
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--walkers', type=int, default=1000)
    parser.add_argument('--lengths', type=int, nargs='+', default=[3, 64, 512])
    parser.add_argument('--seeds', type=int, nargs='+', default=[928, 929, 930])
    parser.add_argument('--warmup', type=int, default=100)
    parser.add_argument('--repeats', type=int, default=100)
    parser.add_argument('--block-size', type=int, default=128)
    parser.add_argument('--device', type=int, default=0)
    parser.add_argument('--output', type=Path, default=Path('dist/gpu-layout'))
    parser.add_argument('--profile', action='store_true', help='Also measure kernels with Nsight Systems')
    parser.add_argument('--replay', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.replay:
        execute_cases(json.loads((output / 'inputs.json').read_text()), output, True)
        return
    if min(args.walkers, *args.lengths, args.repeats) <= 0 or args.warmup < 0:
        parser.error('walkers, lengths and repeats must be positive; warmup nonnegative')
    if len(set(args.lengths)) != len(args.lengths) or len(set(args.seeds)) != len(args.seeds):
        parser.error('lengths and seeds must be distinct')
    if args.profile and not shutil.which('nsys'):
        parser.error('--profile requires NVIDIA Nsight Systems (nsys) on PATH')
    output.mkdir(parents=True, exist_ok=False)
    from jaclang.runtime.gpu import GpuWalkerRuntime
    from jaclang.runtime.runtime import JacRuntime

    repo = Path(__file__).resolve().parents[2]
    chain = JacRuntime.jac_import(target='chain', base_path=str(repo / 'jac/examples/gpu'))[0]
    started = time.perf_counter()
    runtime = GpuWalkerRuntime(chain.ChainSum, device=args.device, block_size=args.block_size)
    compile_ms = (time.perf_counter() - started) * 1000
    manifest = dict(walkers=args.walkers, device=args.device, block_size=args.block_size,
                    warmup=args.warmup, repeats=args.repeats, compile_ms=compile_ms,
                    timestamp_utc=datetime.now(timezone.utc).isoformat(),
                    python=sys.version, byteorder=sys.byteorder,
                    benchmark_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    kernel=runtime.schema.kernel_name,
                    ptx_sha256=hashlib.sha256(runtime.schema.ptx.encode()).hexdigest(),
                    source_sha256=runtime.schema.source_sha256,
                    commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                   cwd=repo, text=True).strip(),
                    cases=[])
    (output / 'chain.ptx').write_text(runtime.schema.ptx)
    try:
        for length in args.lengths:
            print(f'Preparing {args.walkers} real Jac walkers x {length} nodes...', flush=True)
            with memory_context():
                case = prepare_case(runtime, chain, args.walkers, length, args.seeds, output)
            manifest['cases'].append(case)
            print(f"Graph {case['graph_build_ms']:.1f} ms, pack {case['pack_ms']:.1f} ms", flush=True)
    finally:
        runtime.close()
    write_json(output / 'inputs.json', manifest)
    wall = execute_cases(manifest, output)
    summary = dict(gpu=wall['gpu'], execute_wall_us=summarize(wall['records'], 'execute_us'))
    if args.profile:
        prefix = output / 'trace'
        with (output / 'nsys.log').open('w') as log:
            subprocess.run([
                'nsys', 'profile', '--trace=cuda', '--sample=none', '--cpuctxsw=none',
                '--capture-range=cudaProfilerApi', '--capture-range-end=stop',
                '--output=' + str(prefix), sys.executable, '-B', str(Path(__file__).resolve()),
                '--output', str(output), '--replay',
            ], stdout=log, stderr=subprocess.STDOUT, check=True)
            subprocess.run(['nsys', 'export', '--type=sqlite',
                            '--output=' + str(prefix) + '.sqlite', str(prefix) + '.nsys-rep'],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        profile = json.loads((output / 'profile-launches.json').read_text())
        attach_kernel_times(str(prefix) + '.sqlite', profile['records'], manifest['kernel'],
                            args.walkers, args.block_size)
        write_json(output / 'profile-launches.json', profile)
        summary['kernel_us'] = summarize(profile['records'], 'kernel_us')
    write_json(output / 'summary.json', summary)
    print(json.dumps(summary, indent=2), flush=True)
    print(f'Raw samples and verified packed inputs: {output}', flush=True)


if __name__ == '__main__':
    main()
