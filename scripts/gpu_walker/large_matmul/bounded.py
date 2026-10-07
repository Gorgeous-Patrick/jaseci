"""Real Jac shared-input graph and bounded named-cursor CUDA execution.

No dense address surrogate: packing always traverses actual Scalar/RowNext/
ColumnNext objects. Each output is a distinct Dot lane, batched in row-major
order. Read-only packed graph allocations persist across batches.
"""
from array import array
import ctypes as c
from dataclasses import replace
import hashlib
from pathlib import Path
import time


def rss():
    values = {}
    for line in Path('/proc/self/status').read_text().splitlines():
        if line.startswith(('VmRSS:', 'VmHWM:')):
            key, value, _ = line.split()
            values[key[:-1]] = int(value) * 1024
    return values


def guard(limit_gib, reserve_gib=20):
    available = next(int(line.split()[1]) * 1024 for line in
                     Path('/proc/meminfo').read_text().splitlines()
                     if line.startswith('MemAvailable:'))
    if rss()['VmRSS'] > limit_gib * 2**30 or available < reserve_gib * 2**30:
        raise MemoryError('Resource guard: RSS budget or available-memory reserve exceeded')


def build_inputs(mod, m, k, n, limit_gib):
    from jaclang.runtime.runtime import JacRuntime
    heads = []
    for width, relation in ((m, mod.RowNext), (n, mod.ColumnNext)):
        group = []
        for index in range(width):
            # Structured integer weights admit exact full-result verification.
            previous = mod.Scalar(value=index + 1)
            group.append(previous)
            for _ in range(1, k):
                successor = mod.Scalar(value=index + 1)
                JacRuntime.connect(previous, successor, relation)
                previous = successor
            if index % 32 == 0:
                guard(limit_gib)
        heads.append(group)
    return heads


def planning_bindings(mod, heads):
    left, right = heads
    # First-occurrence seed order equals all M*N row-major lanes. Repeated
    # seeds affect execution events, not layout discovery; all outputs execute
    # later, independently, and no event is removed there.
    bindings = [dict(a=left[0], b=node) for node in right]
    bindings += [dict(a=node, b=right[0]) for node in left[1:]]
    return [mod.Dot() for _ in bindings], bindings


def axis_heads(buffers, m, n):
    lanes = m + n - 1
    return (array('q', [buffers.heads[0]]) + array('q', buffers.heads[n:lanes]),
            array('q', buffers.heads[lanes:lanes+n]))


def bind(buffers, axes, start, count, n):
    left, right = axes
    heads = array('q', (left[lane // n] for lane in range(start, start+count)))
    heads.extend(right[lane % n] for lane in range(start, start+count))
    return replace(buffers, heads=heads, seed_counts=array('q', [1]) * (2*count),
                   initial=array('q', [0]) * count, results=array('q', [0]) * count,
                   status=array('I', [0xffffffff]) * count,
                   queue=array('q', heads), prediction={}, timings={})


def digest(values):
    return hashlib.sha256(memoryview(values).cast('B')).hexdigest()


class Resident:
    """Same production PTX ABI; graph H2D once, lane bindings per batch.

    CUDA event kernel intervals include host enqueue gaps. Nsight timelines are
    required for kernel-duration attribution; counters are separate evidence.
    """
    def __init__(self, schema, buffers, capacity, block_size=128):
        from jaclang.runtime.gpu_cuda import CudaSession
        from jaclang.runtime.gpu_cursors import validate_buffers
        if (len(buffers.cursor_spec.cursor_names)!=2 or len(buffers.columns())!=1
                or len(buffers.initial_columns())!=1 or len(buffers.result_columns())!=1
                or buffers.reports is not None or buffers.queue_capacity!=1
                or any(size!=1 for size in buffers.seed_counts)):
            raise ValueError('This experimental resident runner requires two single-seed cursors, one node/state int64 field, no reports and queue capacity one')
        if capacity<1 or capacity>32768:
            raise ValueError('Resident lane capacity must be 1..32768')
        self.capacity=capacity
        self.session = CudaSession(schema.ptx, schema.kernel_name,
                                   graph_format='csr', block_size=block_size,
                                   node_dtypes=schema.node_types(),
                                   state_dtypes=schema.state_types())
        self.call = self.session.driver.call
        self.allocations, self.graph, self.private, self.events = [], [], [], []
        validate_buffers(buffers, self.session)
        self.call('cuCtxPushCurrent_v2', self.session.context)
        try:
            self.graph_h2d_s = 0
            for data in buffers.arrays()[:4]:
                address = self.allocate(len(data)*data.itemsize)
                self.graph.append(address)
                start = time.perf_counter()
                self.session.transfer('cuMemcpyHtoD_v2', address, data)
                self.graph_h2d_s += time.perf_counter()-start
            for width in (16, 16, 8, 8, 4, 16):
                self.private.append(self.allocate(capacity*width))
            signatures = {'cuEventCreate': [c.POINTER(c.c_void_p), c.c_uint],
                'cuEventRecord': [c.c_void_p, c.c_void_p],
                'cuEventSynchronize': [c.c_void_p],
                'cuEventElapsedTime': [c.POINTER(c.c_float), c.c_void_p, c.c_void_p],
                'cuEventDestroy_v2': [c.c_void_p]}
            for name, args in signatures.items():
                fn = getattr(self.session.driver.library, name)
                fn.argtypes, fn.restype = args, c.c_int
            for _ in range(2):
                event = c.c_void_p()
                self.call('cuEventCreate', c.byref(event), 0)
                self.events.append(event)
        finally:
            self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))

    def allocate(self, size):
        address = c.c_uint64()
        self.call('cuMemAlloc_v2', c.byref(address), max(size, 8))
        self.allocations.append(address.value)
        return address.value

    def run(self, buffers, replays=1):
        count = len(buffers.status)
        if not 1<=count<=self.capacity or replays<1:
            raise ValueError('Batch exceeds resident allocation or invalid replay count')
        if (count+self.session.block_size-1)//self.session.block_size > self.session.max_grid:
            raise ValueError('Grid exceeds actual device limit')
        self.call('cuCtxPushCurrent_v2', self.session.context)
        try:
            started = time.perf_counter()
            for address, data in zip(self.private, buffers.arrays()[4:]):
                self.session.transfer('cuMemcpyHtoD_v2', address, data)
            h2d = time.perf_counter()-started
            holders = [c.c_uint64(v) for v in self.graph+self.private+buffers.arguments()]
            params = (c.c_void_p * len(holders))(*(c.addressof(v) for v in holders))
            samples = []
            for _ in range(replays):
                self.call('cuEventRecord', self.events[0], None)
                self.call('cuLaunchKernel', self.session.function,
                          (count+self.session.block_size-1)//self.session.block_size,
                          1, 1, self.session.block_size, 1, 1, 0, None, params, None)
                self.call('cuEventRecord', self.events[1], None)
                self.call('cuEventSynchronize', self.events[1])
                elapsed = c.c_float()
                self.call('cuEventElapsedTime', c.byref(elapsed), *self.events)
                samples.append(elapsed.value * .001)
            started = time.perf_counter()
            for address, data in zip(self.private[3:5], (buffers.results, buffers.status)):
                self.session.transfer('cuMemcpyDtoH_v2', address, data)
            d2h = time.perf_counter()-started
            if any(buffers.status):
                raise AssertionError('Nonzero GPU execution status')
            return dict(binding_H2D_s=h2d, kernel_event_s=samples, D2H_s=d2h)
        finally:
            self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))

    def close(self):
        self.call('cuCtxPushCurrent_v2', self.session.context)
        try:
            for event in self.events:
                self.call('cuEventDestroy_v2', event)
            for address in reversed(self.allocations):
                self.call('cuMemFree_v2', address)
        finally:
            self.call('cuCtxPopCurrent_v2', c.byref(c.c_void_p()))
            self.session.close()
