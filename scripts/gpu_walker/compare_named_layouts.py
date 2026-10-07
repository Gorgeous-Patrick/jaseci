"""Rigorous physical-layout comparison: legacy chains, named cursors, matmul.

Real CUDA only. Save typed packed inputs for checksum-verified profiler replay.
Randomization changes physical node indices only, never graph edges or lanes.
"""
import argparse
from array import array
import csv
from datetime import datetime, timezone
import gc
import hashlib
import json
from pathlib import Path
import random
import shutil
import subprocess
import sys
import time

from compare_layouts import distribution, memory_context, telemetry, write_json
from layout_benchmark import (MeasuredSession, assert_values, attach_profile,
                              paired_order, permutation, permute_cursors, summarize)
from verify import reorder_nodes

REPO = Path(__file__).resolve().parents[2]


def parse_shapes(values, rank):
    result = []
    for value in values:
        shape = tuple(int(part) for part in value.lower().split('x'))
        if len(shape) != rank or min(shape) < 1:
            raise ValueError(f'Expected {rank} positive dimensions: {value}')
        if shape in result:
            raise ValueError(f'Duplicate shape: {value}')
        result.append(shape)
    return result


def save_array(path, data):
    payload = data.tobytes()
    path.write_bytes(payload)
    return dict(path=str(path), type=data.typecode, count=len(data),
                sha256=hashlib.sha256(payload).hexdigest())


def load_array(info):
    data = Path(info['path']).read_bytes()
    if hashlib.sha256(data).hexdigest() != info['sha256']:
        raise ValueError('Packed input checksum mismatch')
    values = array(info['type']); values.frombytes(data)
    if len(values) != info['count']:
        raise ValueError('Packed input length mismatch')
    return values


def save_layout(folder, label, buffers, timings, seed=None):
    arrays = buffers.arrays()
    files = [save_array(folder / f'{label}-{i}.bin', buf) for i, buf in enumerate(arrays)]
    identity_order = getattr(buffers, 'prediction', {}).get('order')
    return dict(label=label, seed=seed, files=files, timings=timings,
                identity_order=identity_order,
                prediction_strategy=getattr(buffers, 'prediction', {}).get('strategy'),
                identity_order_sha256=hashlib.sha256(array('q', identity_order).tobytes()).hexdigest() if identity_order is not None else None,
                payload_bytes=sum(len(buf) * buf.itemsize for buf in arrays),
                queue_capacity=getattr(buffers, 'queue_capacity', None),
                max_visits=getattr(buffers, 'max_visits', None))


def load_layout(info, schema):
    from jaclang.runtime.gpu_memory import ChainBuffers
    from jaclang.runtime.gpu_cursors import CursorBuffers
    arrays = [load_array(f) for f in info['files']]
    if schema.cursor_spec is None:
        return ChainBuffers(*arrays)
    f, s = len(schema.field_paths()), len(schema.state_paths())
    tags, offsets, targets, heads, counts = arrays[f:f + 5]
    initial = arrays[f + 5:f + 5 + s]
    results = arrays[f + 5 + s:f + 5 + 2 * s]
    status, queue = arrays[-2:]
    return CursorBuffers(schema.cursor_spec, arrays[:f], tags, offsets, targets,
                         heads, counts, initial[0], results[0], status, queue,
                         info['queue_capacity'], info['max_visits'], initial[1:], results[1:],
                         timings={}, prediction={})


def write_csv(path, records):
    keys = sorted({key for record in records for key in record})
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=keys)
        writer.writeheader(); writer.writerows(records)


def prepare_case(kind, shape, schemas, modules, seeds, output, queue_capacity):
    from jaclang.runtime.runtime import JacRuntime
    from jaclang.runtime import gpu, gpu_cursors, gpu_memory
    source_key = 'Chain' if kind == 'chain' else 'Dot'
    schema = schemas[source_key]
    label = kind + '-' + 'x'.join(map(str, shape))
    folder = output / label; folder.mkdir()
    started = time.perf_counter()
    if kind == 'chain':
        count, length = shape; mod = modules['Chain']
        nodes = [mod.Cell(value=float(i + 1)) for i in range(count * length)]
        for base in range(0, len(nodes), length):
            for hop in range(length - 1):
                JacRuntime.connect(nodes[base + hop], nodes[base + hop + 1], mod.Next)
        starts = nodes[::length]
        walkers = [mod.ChainSum(total=float(i * 10)) for i in range(count)]
        build_ms = (time.perf_counter() - started) * 1000
        oracle_started = time.perf_counter()
        expected = [float(i * 10 + length * (2 * i * length + length + 1) // 2)
                    for i in range(count)]
    elif kind == 'dot':
        count, length = shape; mod = modules['Dot']; starts = []
        for lane in range(count):
            a = [mod.Scalar(value=(lane + k) % 7 - 3) for k in range(length)]
            b = [mod.Scalar(value=(lane * 3 + k) % 11 - 5) for k in range(length)]
            for left, right, edge in ((a, b, mod.RowNext), (b, a, mod.ColumnNext)):
                for x, y in zip(left, left[1:]): JacRuntime.connect(x, y, edge)
            starts.append(dict(a=a[0], b=b[0]))
        walkers = [mod.Dot() for _ in range(count)]
        build_ms = (time.perf_counter() - started) * 1000
        oracle_started = time.perf_counter()
        expected = [sum(((lane + k) % 7 - 3) * ((lane * 3 + k) % 11 - 5)
                        for k in range(length)) for lane in range(count)]
    else:
        m, k, n = shape; mod = modules['Dot']
        a = [[(i + q) % 7 - 3 for q in range(k)] for i in range(m)]
        b = [[(q * 3 + j) % 11 - 5 for j in range(n)] for q in range(k)]
        walkers, starts, output_nodes = mod.build_matmul(a, b)
        count = m * n
        build_ms = (time.perf_counter() - started) * 1000
        oracle_started = time.perf_counter()
        expected = [sum(a[i][q] * b[q][j] for q in range(k)) for i in range(m) for j in range(n)]
    oracle_ms = (time.perf_counter() - oracle_started) * 1000
    expected_nodes = shape[0] * shape[1] if kind == 'chain' else (2 * shape[0] * shape[1] if kind == 'dot' else (shape[0] + shape[2]) * shape[1])

    def pack(layout, seed=0):
        before = time.perf_counter()
        if source_key == 'Chain':
            batch = gpu.pack_walkers(schema, walkers, starts)
            timing = dict(pack_ms=(time.perf_counter() - before) * 1000, predict_ms=0.0, remap_soa_ms=None)
            buffers = batch.buffers
            if layout == 'Random':
                shuffled_at = time.perf_counter()
                order = permutation(len(batch.nodes), seed)
                values, links, heads = reorder_nodes(buffers.values, buffers.links, buffers.heads, order)
                buffers = gpu_memory.chain_buffers(values, links, heads, list(buffers.initial))
                timing['permutation_ms'] = (time.perf_counter() - shuffled_at) * 1000
                timing['pack_ms'] = (time.perf_counter() - before) * 1000
        else:
            batch = gpu_cursors.pack_cursors(schema, walkers, starts, queue_capacity,
                layout='predicted' if layout == 'Predicted' else 'current')
            buffers = batch.buffers; timing = dict(buffers.timings)
            if layout == 'Random':
                shuffled_at = time.perf_counter()
                buffers = permute_cursors(buffers, permutation(len(batch.nodes), seed))
                timing['permutation_ms'] = (time.perf_counter() - shuffled_at) * 1000
                timing['pack_ms'] = (time.perf_counter() - before) * 1000
        if len(batch.nodes) != expected_nodes:
            raise AssertionError('Input identities are not shared as expected')
        return buffers, timing

    # All lanes use an independent arithmetic oracle; ordinary Jac checks a bounded subset.
    cpu_started = time.perf_counter()
    for lane in sorted({0, count // 2, count - 1}):
        w = schema.walker_type(total=float(lane * 10) if source_key == 'Chain' else 0)
        JacRuntime.spawn(starts[lane], w)
        assert_values([w.total], [expected[lane]], schema.dtype.value)
    cpu_reference_ms = (time.perf_counter() - cpu_started) * 1000
    layouts = []
    current, timing = pack('Current')
    layouts.append(save_layout(folder, 'Current', current, timing))
    if source_key == 'Dot':
        predicted, timing = pack('Predicted')
        layouts.append(save_layout(folder, 'Predicted', predicted, timing))
    for seed in seeds:
        # Permute the SAME unique packed graph, not an independently built graph.
        before = time.perf_counter()
        if source_key == 'Chain':
            values, links, heads = reorder_nodes(current.values, current.links, current.heads,
                                                 permutation(expected_nodes, seed))
            shuffled = gpu_memory.chain_buffers(values, links, heads, list(current.initial))
        else:
            shuffled = permute_cursors(current, permutation(expected_nodes, seed))
        reorder_ms = (time.perf_counter() - before) * 1000
        random_timing = dict(layouts[0]['timings'], permutation_ms=reorder_ms)
        random_timing['pack_ms'] += reorder_ms
        layouts.append(save_layout(folder, f'Random-{seed}', shuffled, random_timing, seed))
    expected_file = save_array(folder / 'expected.bin', array('d' if source_key == 'Chain' else 'q', expected))
    case = dict(id=label, kind=kind, shape=shape, source_key=source_key,
                graph_build_ms=build_ms, oracle_ms=oracle_ms, cpu_reference_ms=cpu_reference_ms,
                walkers=count, nodes=expected_nodes, dtype=schema.dtype.value,
                expected=expected_file, layouts=layouts,
                kernel=schema.kernel_name, graph_format=schema.graph_format)
    return case, pack


def run_case(case, schemas, args, pack=None):
    schema = schemas[case['source_key']]
    expected = list(load_array(case['expected']))
    infos = {info['label']: info for info in case['layouts']}
    measured = {}; records = []
    try:
        for label, info in infos.items():
            buffers = load_layout(info, schema)
            session = MeasuredSession(schema, buffers, expected, args.block_size, args.device)
            measured[label] = session
            result = session.execute()
            records.append(dict(case=case['id'], layout=label.split('-')[0], seed=info['seed'],
                                phase='initialization', pair=-1, mode='initialize', **result))
        peer_values = list(measured['Current'].buffers.results)
        for session in measured.values():
            assert_values(session.buffers.results, peer_values, schema.dtype.value)
        modes = ('resident', 'one_shot')
        for seed in args.seeds:
            names = ['Current'] + (['Predicted'] if 'Predicted' in measured else []) + ['Random']
            keys = {name: f'Random-{seed}' if name == 'Random' else name for name in names}
            for mode in modes:
                for phase, pair, label in paired_order(seed, args.warmup, args.repeats, names):
                    session = measured[keys[label]]
                    info = infos[keys[label]]
                    if mode == 'resident':
                        result = session.resident(); host_timing = None
                    else:
                        if pack is not None:
                            fresh, host_timing = pack(label, seed)
                            # Fresh packing must reconstruct precisely the saved physical layout.
                            for fresh_arr, saved in zip(fresh.arrays(), info['files']):
                                if fresh_arr is fresh.results or fresh_arr is fresh.status:
                                    continue
                                if hashlib.sha256(fresh_arr.tobytes()).hexdigest() != saved['sha256']:
                                    raise AssertionError('Packing changed immutable input or physical permutation')
                            session.buffers = fresh
                        else:
                            host_timing = info['timings']
                        result = session.execute()
                    assert_values(session.buffers.results, peer_values, schema.dtype.value)
                    record = dict(case=case['id'], layout=label, seed=seed, phase=phase,
                                  pair=pair, mode=mode, **result)
                    if host_timing is not None:
                        for field, val in host_timing.items():
                            record[field.removesuffix('_ms') + '_us'] = val * 1000 if val is not None else None
                        record['pack_through_D2H_us'] = host_timing['pack_ms'] * 1000 + result['execute_wall_us']
                        record['graph_through_D2H_us'] = case['graph_build_ms'] * 1000 + record['pack_through_D2H_us']
                    records.append(record)
        return records
    finally:
        for session in measured.values(): session.close()


def schemas_and_modules(source_keys=None):
    from jaclang.runtime.runtime import JacRuntime
    from jaclang.runtime import gpu
    from jaclang.compiler.backends.native.llvm import binding as llvm
    llvm.initialize_all_targets(); llvm.initialize_all_asmprinters()
    folder = REPO / 'jac/examples/gpu'
    selected = set(('Chain', 'Dot') if source_keys is None else source_keys)
    if not selected or not selected <= {'Chain', 'Dot'}:
        raise ValueError('Select Chain and/or Dot schemas')
    modules = {key: JacRuntime.jac_import(target=name, base_path=str(folder))[0]
               for key, name in (('Chain', 'chain'), ('Dot', 'named_cursors')) if key in selected}
    schemas = {key: gpu.walker_schema(getattr(module, 'ChainSum' if key == 'Chain' else 'Dot'),
                                    'chain' if key == 'Chain' else 'csr')
               for key, module in modules.items()}
    return schemas, modules


def execute_replay(manifest, args, schemas):
    from jaclang.runtime.gpu_cuda import CudaSession
    schema = next(iter(schemas.values()))
    sentinel = CudaSession(schema.ptx, schema.kernel_name)
    driver = sentinel.driver
    for name in ('cuProfilerStart', 'cuProfilerStop'):
        fn = getattr(driver.library, name); fn.argtypes, fn.restype = [], c_int_type()
    driver.call('cuCtxPushCurrent_v2', sentinel.context)
    records = []
    try:
        driver.call('cuProfilerStart')
        for case in manifest['cases']:
            records.extend(run_case(case, schemas, args))
        driver.call('cuProfilerStop')
    finally:
        import ctypes as c
        driver.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))
        sentinel.close()
    write_json(args.output / 'profile-launches.json', dict(records=records))


def c_int_type():
    import ctypes as c
    return c.c_int


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chain-cases', nargs='*', default=['128x8', '1024x64', '2048x64'])
    parser.add_argument('--dot-cases', nargs='*', default=['128x8', '1024x32'])
    parser.add_argument('--matmul-cases', nargs='*', default=['16x32x24', '32x64x48', '64x128x64', '128x256x128'])
    parser.add_argument('--seeds', nargs='+', type=int, default=[928, 929, 930])
    parser.add_argument('--warmup', type=int, default=6)
    parser.add_argument('--repeats', type=int, default=16)
    parser.add_argument('--block-size', type=int, default=128)
    parser.add_argument('--device', type=int, default=0)
    parser.add_argument('--queue-capacity', type=int, default=2)
    parser.add_argument('--max-nodes', type=int, default=150000)
    parser.add_argument('--max-walkers', type=int, default=32768)
    parser.add_argument('--max-payload-mib', type=int, default=256)
    parser.add_argument('--output', type=Path, default=Path('dist/gpu-layout-cursors'))
    parser.add_argument('--profile', action='store_true')
    parser.add_argument('--replay', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args(); args.output = args.output.resolve()
    if args.replay:
        manifest = json.loads((args.output / 'inputs.json').read_text())
        for key in ('seeds', 'warmup', 'repeats', 'block_size', 'device'):
            setattr(args, key, manifest[key])
        schemas, modules = schemas_and_modules(manifest['sources'])
        for key, schema in schemas.items():
            if hashlib.sha256(schema.ptx.encode()).hexdigest() != manifest['sources'][key]['ptx_sha256']:
                raise ValueError('PTX changed since packed input recording')
        execute_replay(manifest, args, schemas); return
    if args.warmup < 1 or args.repeats < 2 or args.queue_capacity < 1 or min(args.max_nodes, args.max_walkers, args.max_payload_mib) < 1:
        parser.error('positive limits and warmup; at least two repeats required')
    if len(args.seeds) < 2 or len(set(args.seeds)) != len(args.seeds) or min(args.seeds) < 0:
        parser.error('at least two distinct nonnegative permutation seeds required')
    if args.profile and not shutil.which('nsys'): parser.error('--profile requires nsys')
    try:
        cases = [('chain', s) for s in parse_shapes(args.chain_cases, 2)] + [('dot', s) for s in parse_shapes(args.dot_cases, 2)] + [('matmul', s) for s in parse_shapes(args.matmul_cases, 3)]
    except ValueError as error: parser.error(str(error))
    if not cases: parser.error('at least one case required')
    for kind, s in cases:
        walkers = s[0] * s[2] if kind == 'matmul' else s[0]
        nodes = (s[0] + s[2]) * s[1] if kind == 'matmul' else s[0] * s[1] * (2 if kind == 'dot' else 1)
        cpu_nodes = nodes + (walkers if kind == 'matmul' else 0)
        rough_payload = nodes * (40 if kind != 'chain' else 16) + walkers * (64 + 16 * args.queue_capacity)
        if cpu_nodes > args.max_nodes or walkers > args.max_walkers or rough_payload > args.max_payload_mib * 1024**2:
            parser.error(f'Case {kind} {s} exceeds configured host/device bounds')
    args.output.mkdir(parents=True, exist_ok=False)
    before = telemetry(); started = time.perf_counter()
    schemas, modules = schemas_and_modules({'Chain' if kind == 'chain' else 'Dot' for kind, _ in cases})
    source_paths = ['scripts/gpu_walker/compare_named_layouts.py', 'scripts/gpu_walker/layout_benchmark.py',
                    'scripts/gpu_walker/compare_layouts.py', 'jac/jaclang/runtime/gpu_cursors.py',
                    'jac/jaclang/runtime/gpu.jac', 'jac/jaclang/runtime/gpu_cuda.jac',
                    'jac/jaclang/compiler/backends/native/ptx_walker.jac',
                    'jac/jaclang/compiler/backends/native/ptx_csr.jac']
    manifest = dict(timestamp_utc=datetime.now(timezone.utc).isoformat(), command=sys.argv,
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),
        source_hashes={p:hashlib.sha256((REPO/p).read_bytes()).hexdigest() for p in source_paths},
        dirty_worktree=True, python=sys.version, seeds=args.seeds, warmup=args.warmup, repeats=args.repeats,
        block_size=args.block_size, device=args.device, queue_capacity=args.queue_capacity,
        max_nodes=args.max_nodes, max_walkers=args.max_walkers, max_payload_mib=args.max_payload_mib,
        setup_compile_ms=(time.perf_counter()-started)*1000, telemetry_before=before,
        sources={}, cases=[], timing_contract='event intervals include host enqueue gaps; profiler is exact kernel interval; graph cost is composed from separately measured build')
    for key, schema in schemas.items():
        (args.output/f'{key}.ptx').write_text(schema.ptx)
        manifest['sources'][key] = dict(kernel=schema.kernel_name,source_sha256=schema.source_sha256,
            ptx_sha256=hashlib.sha256(schema.ptx.encode()).hexdigest(),dtype=schema.dtype.value)
    records = []
    for kind, shape in cases:
        print(f'Preparing {kind} {shape}',flush=True)
        with memory_context():
            case, pack = prepare_case(kind, shape, schemas, modules, args.seeds, args.output, args.queue_capacity)
            manifest['cases'].append(case)
            records.extend(run_case(case, schemas, args, pack))
            del pack
        gc.collect()
        print(f'{case["id"]}: all CPU/layout checks PASS',flush=True)
    manifest['telemetry_after'] = telemetry()
    write_json(args.output/'inputs.json',manifest)
    write_json(args.output/'wall-events.json',dict(records=records))
    write_csv(args.output/'wall-events.csv',records)
    summary = dict(evidence='actual CUDA',event_wall=summarize(records))
    if args.profile:
        prefix=args.output/'trace'
        with (args.output/'nsys.log').open('w') as log:
            subprocess.run(['nsys','profile','--trace=cuda','--sample=none','--cpuctxsw=none',
                '--capture-range=cudaProfilerApi','--capture-range-end=stop','--output='+str(prefix),
                sys.executable,'-B',str(Path(__file__).resolve()),'--output',str(args.output),'--replay'],
                stdout=log,stderr=subprocess.STDOUT,check=True)
            subprocess.run(['nsys','export','--type=sqlite','--output='+str(prefix)+'.sqlite',str(prefix)+'.nsys-rep'],
                stdout=log,stderr=subprocess.STDOUT,check=True)
        profiled=json.loads((args.output/'profile-launches.json').read_text())['records']
        geometries={case['id']:[case['kernel'],(case['walkers']+args.block_size-1)//args.block_size,1,1,args.block_size,1,1] for case in manifest['cases']}
        attach_profile(str(prefix)+'.sqlite',profiled,geometries)
        write_json(args.output/'profile-launches.json',dict(records=profiled))
        write_csv(args.output/'profile-launches.csv',profiled)
        summary['profiled']=summarize(profiled)
    write_json(args.output/'summary.json',summary)
    print(json.dumps(summary,indent=2),flush=True)
    print('Raw inputs, CSV, JSON and provenance:',args.output,flush=True)


if __name__=='__main__': main()
