"""Shared semantic permutation, paired sampling, and real CUDA measurements.

Host timings are instrumented wall times. CUDA event intervals and Nsight kernel
intervals are recorded separately; an event interval can include enqueue gaps.
"""
from array import array
from dataclasses import replace
import ctypes as c
import random
import struct
import time

from compare_layouts import distribution


def permutation(count, seed):
    order = list(range(count))
    random.Random(seed).shuffle(order)
    return order


def remap_indices(values, old_to_new):
    return array('q', (old_to_new[v] if v >= 0 else v for v in values))


def permute_cursors(buffers, order):
    """Permute unique physical slots, preserving every lane and ordered CSR row."""
    n = len(buffers.tags)
    if sorted(order) != list(range(n)):
        raise ValueError('Node order must be a bijection of physical node indices')
    old_to_new = {old: new for new, old in enumerate(order)}
    offsets, targets = [], []
    for channel in range(len(buffers.cursor_spec.cursor_names)):
        offsets.append(len(targets))
        for old in order:
            row = channel * (n + 1) + old
            start, end = buffers.offsets[row:row + 2]
            targets.extend(old_to_new[v] for v in buffers.targets[start:end])
            offsets.append(len(targets))
    result = replace(
        buffers,
        node_columns=[array(col.typecode, (col[old] for old in order))
                      for col in buffers.columns()],
        tags=array('q', (buffers.tags[old] for old in order)),
        offsets=array('q', offsets), targets=array('q', targets),
        heads=remap_indices(buffers.heads, old_to_new),
        seed_counts=array('q', buffers.seed_counts),
        queue=remap_indices(buffers.queue, old_to_new),
        initial=array(buffers.initial.typecode, buffers.initial),
        results=array(buffers.results.typecode, [0]) * len(buffers.status),
        status=array('I', [0xffffffff]) * len(buffers.status),
        extra_initial=[array(a.typecode, a) for a in buffers.extra_initial],
        extra_results=[array(a.typecode, [0]) * len(a) for a in buffers.extra_results],
        timings={}, prediction=dict(layout='permutation', strategy='physical_random_permutation', order=order))
    if buffers.reports is not None:
        result.reports = replace(buffers.reports,
            counts=array('Q', [0]) * len(buffers.reports.counts),
            values=array(buffers.reports.values.typecode, [0]) * len(buffers.reports.values),
            tags=array('Q', [0]) * len(buffers.reports.tags) if buffers.reports.tags is not None else None)
    return result


def paired_order(seed, warmup, repeats, labels):
    """Same seed/pair for all layouts; shuffled order is reproducible and paired."""
    for phase, rounds in (('warmup', warmup), ('measured', repeats)):
        for pair in range(rounds):
            order = list(labels)
            random.Random((seed << 32) + pair + (0 if phase == 'warmup' else 104729)).shuffle(order)
            for label in order:
                yield phase, pair, label


def assert_values(actual, expected, dtype):
    if len(actual) != len(expected):
        raise AssertionError('Output lane count changed')
    for lane, (a, b) in enumerate(zip(actual, expected)):
        valid = struct.pack('=d', a) == struct.pack('=d', b) if dtype == 'float64' else a == b
        if not valid:
            raise AssertionError(f'CPU reference mismatch at lane {lane}: {a} != {b}')


def summarize(records):
    metrics = ('pack_us', 'collect_us', 'predict_us', 'remap_soa_us', 'permutation_us', 'H2D_us', 'kernel_event_us', 'kernel_profiler_us', 'D2H_us',
               'execute_wall_us', 'pack_through_D2H_us', 'graph_through_D2H_us')
    result = []
    for case in sorted({r['case'] for r in records}):
        for mode in ('resident', 'one_shot'):
            rows = [r for r in records if r['case'] == case and r['mode'] == mode
                    and r['phase'] == 'measured']
            if not rows:
                continue
            labels = sorted({r['layout'] for r in rows})
            item = dict(case=case, mode=mode, units='us', distributions={}, paired_ratios={})
            for metric in metrics:
                measured = [r for r in rows if r.get(metric) is not None]
                if not measured:
                    continue
                item['distributions'][metric] = {
                    label: distribution([r[metric] for r in measured if r['layout'] == label])
                    for label in labels if any(r['layout'] == label for r in measured)}
                pairs = {}
                for r in measured:
                    pairs.setdefault((r['seed'], r['pair']), {})[r['layout']] = r[metric]
                for baseline in ('Current', 'Predicted'):
                    if baseline in labels and 'Random' in labels:
                        ratios = [p['Random'] / p[baseline] for p in pairs.values()
                                  if baseline in p and 'Random' in p and p[baseline] > 0]
                        if ratios:
                            item['paired_ratios'][f'Random_over_{baseline}_{metric}'] = distribution(ratios)
            result.append(item)
    return result


def attach_profile(database, records, geometries):
    """One launch per record, including initialization; reject any trace mismatch."""
    import sqlite3
    with sqlite3.connect(database) as db:
        rows = db.execute('''SELECT k.end-k.start, s.value, k.gridX, k.gridY, k.gridZ,
                            k.blockX, k.blockY, k.blockZ
                            FROM CUPTI_ACTIVITY_KIND_KERNEL k
                            JOIN StringIds s ON k.shortName=s.id ORDER BY k.start''').fetchall()
    if len(rows) != len(records):
        raise ValueError(f'Incomplete trace: {len(rows)} kernels for {len(records)} recorded launches')
    for record, row in zip(records, rows):
        if row[0] <= 0 or row[1:] != tuple(geometries[record['case']]):
            raise ValueError(f'Unexpected kernel or geometry: {record["case"]}: {row}')
        record['kernel_profiler_us'] = row[0] / 1000


class MeasuredSession:
    """Uses the production launcher; direct replay retains the same device inputs.

    One-node channel seeds are reinitialized by the device kernel on each launch.
    General seed lists require scratch restoration and are rejected for residency.
    All measured launches are checked against the CPU oracle and peer layout.
    """
    def __init__(self, schema, buffers, expected, block_size=128, device=0):
        from jaclang.runtime.gpu_cuda import CudaSession
        self.buffers, self.schema, self.expected = buffers, schema, expected
        self.named = hasattr(buffers, 'cursor_spec')
        if schema.emits_reports:
            raise ValueError('This performance suite measures report-free walkers')
        if self.named and any(size > 1 for size in buffers.seed_counts):
            raise ValueError('Resident replay currently requires at most one seed per channel/lane')
        self.session = CudaSession(schema.ptx, schema.kernel_name, device=device,
            block_size=block_size, graph_format=schema.graph_format,
            node_field_count=len(schema.field_paths()), state_field_count=len(schema.state_paths()),
            node_dtypes=schema.node_types(), state_dtypes=schema.state_types())
        self.driver = self.session.driver
        self.call = self.driver.call
        self.argument_count = len(buffers.arrays()) + (5 if self.named else 2)
        self.arguments = None
        self.events = []
        self.metrics = {}
        self.driver.call = self._call
        try:
            signatures = {
                'cuEventCreate': [c.POINTER(c.c_void_p), c.c_uint],
                'cuEventDestroy_v2': [c.c_void_p],
                'cuEventRecord': [c.c_void_p, c.c_void_p],
                'cuEventSynchronize': [c.c_void_p],
                'cuEventElapsedTime': [c.POINTER(c.c_float), c.c_void_p, c.c_void_p]}
            for name, args in signatures.items():
                fn = getattr(self.driver.library, name)
                fn.argtypes, fn.restype = args, c.c_int
            self.call('cuCtxPushCurrent_v2', self.session.context)
            try:
                for _ in range(2):
                    event = c.c_void_p()
                    self.call('cuEventCreate', c.byref(event), 0)
                    self.events.append(event)
            finally:
                self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))
        except BaseException:
            self.close()
            raise

    def _call(self, name, *args):
        if name in ('cuMemcpyHtoD_v2', 'cuMemcpyDtoH_v2', 'cuMemAlloc_v2', 'cuMemFree_v2'):
            started = time.perf_counter_ns()
            result = self.call(name, *args)
            key = 'H2D_us' if name == 'cuMemcpyHtoD_v2' else 'D2H_us' if name == 'cuMemcpyDtoH_v2' else 'allocation_us'
            self.metrics[key] = self.metrics.get(key, 0) + (time.perf_counter_ns() - started) / 1000
            return result
        if name == 'cuLaunchKernel':
            params = args[-2]
            self.arguments = [c.cast(params[i], c.POINTER(c.c_uint64))[0]
                              for i in range(self.argument_count)]
            self.call('cuEventRecord', self.events[0], None)
            result = self.call(name, *args)
            self.call('cuEventRecord', self.events[1], None)
            return result
        return self.call(name, *args)

    def _finish(self):
        elapsed = c.c_float()
        self.call('cuEventElapsedTime', c.byref(elapsed), *self.events)
        self.metrics['kernel_event_us'] = elapsed.value * 1000
        assert_values(self.buffers.results, self.expected, self.schema.dtype.value)
        if any(self.buffers.status):
            raise AssertionError(f'GPU statuses: {list(self.buffers.status)}')
        return dict(self.metrics)

    def execute(self):
        self.metrics = dict(H2D_us=0.0, D2H_us=0.0, allocation_us=0.0)
        self.buffers.results[:] = array(self.buffers.results.typecode, [0]) * len(self.expected)
        self.buffers.status[:] = array('I', [0xffffffff]) * len(self.expected)
        started = time.perf_counter_ns()
        self.session.execute(self.buffers)
        wall = (time.perf_counter_ns() - started) / 1000
        self.call('cuCtxPushCurrent_v2', self.session.context)
        try:
            result = self._finish()
        finally:
            self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))
        result['execute_wall_us'] = wall
        return result

    def resident(self):
        if self.arguments is None:
            raise RuntimeError('Upload and verify buffers before resident replay')
        self.metrics = {}
        self.call('cuCtxPushCurrent_v2', self.session.context)
        try:
            # Poison only output buffers outside timers. Inputs and scratch remain resident.
            all_arrays = self.buffers.arrays()
            addresses = {id(buf): addr for buf, addr in zip(all_arrays, self.arguments)}
            outputs = [*self.buffers.result_columns(), self.buffers.status]
            self.buffers.results[:] = array(self.buffers.results.typecode, [0]) * len(self.expected)
            self.buffers.status[:] = array('I', [0xffffffff]) * len(self.expected)
            for buf in outputs:
                self.session.transfer('cuMemcpyHtoD_v2', addresses[id(buf)], buf)
            self.metrics = {}
            holders = [c.c_uint64(v) for v in self.arguments]
            params = (c.c_void_p * len(holders))(*(c.addressof(v) for v in holders))
            count = len(self.expected)
            started = time.perf_counter_ns()
            self.driver.call('cuLaunchKernel', self.session.function,
                (count + self.session.block_size - 1) // self.session.block_size,
                1, 1, self.session.block_size, 1, 1, 0, None, params, None)
            self.call('cuEventSynchronize', self.events[1])
            self.metrics['execute_wall_us'] = (time.perf_counter_ns() - started) / 1000
            for buf in outputs:
                self.session.transfer('cuMemcpyDtoH_v2', addresses[id(buf)], buf)
            result = self._finish()
            result['H2D_us'] = None
            return result
        finally:
            self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))

    def close(self):
        if not self.session.closed:
            self.call('cuCtxPushCurrent_v2', self.session.context)
            try:
                for event in self.events:
                    self.driver.cleanup('cuEventDestroy_v2', event)
            finally:
                self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))
            self.driver.call = self.call
            self.session.close()
