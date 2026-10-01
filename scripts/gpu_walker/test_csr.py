"""CSR traversal, packing and ABI checks; JAC_GPU_TEST_CUDA=1 executes real PTX."""

from array import array
import ctypes as c
import os
from pathlib import Path
import random
import unittest

from test_runtime import DriverDouble


class CpuCsrKernel:
    """Execute the same LLVM traversal on the CPU, with guarded outputs/scratch."""

    def __init__(self, spec):
        from jaclang.compiler.backends.native.ptx_csr import build_csr_module
        from jaclang.compiler.backends.native.llvm import binding as llvm

        target = llvm.Target.from_default_triple().create_target_machine(opt=2)
        module = build_csr_module([spec], target, device=False)
        self.engine = llvm.create_mcjit_compiler(module, target)
        self.engine.finalize_object()
        self.scalar = c.c_int64 if spec.dtype.value == 'int64' else c.c_double
        self.types = (self.scalar, c.c_int64, c.c_int64, c.c_int64,
                      self.scalar, self.scalar, c.c_uint32, c.c_int64)
        self.lane = c.CFUNCTYPE(None, *[c.POINTER(t) for t in self.types],
                               *[c.c_uint64] * 6)(
            self.engine.get_function_address(f'jac_{spec.name}_csr_lane'))

    def run(self, buffers):
        n, e, m = len(buffers.values), len(buffers.targets), len(buffers.heads)
        q = buffers.queue_capacity
        inputs = buffers.arrays()[:5]
        before = [bytes(buf) for buf in inputs]
        ptrs = [c.cast(buf.buffer_info()[0], c.POINTER(typ))
                for buf, typ in zip(inputs, self.types)]
        results = (self.scalar * (m + 2))(*([-987654] * (m + 2)))
        status = (c.c_uint32 * (m + 2))(*([173] * (m + 2)))
        queue = (c.c_int64 * (m * q + 2))()
        queue[0] = queue[-1] = -713
        ptrs += [c.cast(c.byref(results, 8), c.POINTER(self.scalar)),
                 c.cast(c.byref(status, 4), c.POINTER(c.c_uint32)),
                 c.cast(c.byref(queue, 8), c.POINTER(c.c_int64))]
        for lane in reversed(range(m)):
            self.lane(*ptrs, n, e, m, q, buffers.max_visits, lane)
        for count, lane in ((0, 0), (m, m), (m, 2**32), (m, 2**64 - 1)):
            self.lane(*([None] * 8), n, e, count, q, buffers.max_visits, lane)
        assert results[0] == results[-1] == -987654
        assert status[0] == status[-1] == 173
        assert queue[0] == queue[-1] == -713
        assert before == [bytes(buf) for buf in inputs]
        return list(results)[1:-1], list(status)[1:-1]


class CsrDriverDouble(DriverDouble):
    def launch(self, function, gx, gy, gz, bx, by, bz, shared, stream, params, extra):
        if self.fail_launch:
            return 700
        args = [c.cast(params[i], c.POINTER(c.c_uint64))[0] for i in range(13)]
        assert (gy, gz, by, bz, shared, stream, bool(extra)) == (1, 1, 1, 1, 0, None, False)
        assert all(address % 256 == 0 for address in args[:8] if address)
        types = (self.scalar, c.c_int64, c.c_int64, c.c_int64,
                 self.scalar, self.scalar, c.c_uint32, c.c_int64)
        ptrs = [c.cast(address, c.POINTER(typ)) for address, typ in zip(args, types)]
        for lane in reversed(range(gx * bx)):
            self.lane(*ptrs, *args[8:], lane)
        if self.corrupt_status:
            ptrs[6][0] = 1
        self.launches.append((gx, bx, *args[8:]))
        return 0


def flatten(rows):
    offsets, targets = [0], []
    for row in rows:
        targets.extend(row)
        offsets.append(len(targets))
    return offsets, targets


class CsrWalkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from jaclang.runtime.runtime import JacRuntime
        from jaclang.runtime.context import ExecutionContext
        from jaclang.runtime import gpu, gpu_cuda, gpu_memory
        from jaclang.compiler.backends.native.ptx import compile_ptx_frontend
        from jaclang.compiler.backends.native.ptx_walker import select_chain_walkers
        from jaclang.compiler.backends.native.ptx_csr import emit_csr_ptx
        from jaclang.compiler.backends.native.llvm import binding as llvm

        llvm.initialize_all_targets()
        llvm.initialize_all_asmprinters()
        cls.jac, cls.gpu, cls.cuda, cls.memory = JacRuntime, gpu, gpu_cuda, gpu_memory
        cls.emit = staticmethod(emit_csr_ptx)
        cls.on_cuda = os.environ.get('JAC_GPU_TEST_CUDA') == '1'
        base, target = JacRuntime.get_base_path_dir(), JacRuntime.get_full_target_path()
        try:
            JacRuntime.set_base_path(None)
            JacRuntime.set_full_target_path(None)
            cls.context = ExecutionContext()
        finally:
            JacRuntime.set_base_path(base)
            JacRuntime.set_full_target_path(target)
        cls.token = JacRuntime.push_request_context(cls.context)
        folder = Path(__file__).resolve().parents[2] / 'jac/examples/gpu'
        cls.specs, cls.modules = {}, {}
        for file, names in (('csr_graph', ['GraphSum', 'GraphTrace', 'GraphModulo']),
                            ('chain', ['ChainSum']), ('even_chain', ['EvenSum'])):
            module = JacRuntime.jac_import(target=file, base_path=str(folder))[0]
            specs = select_chain_walkers(compile_ptx_frontend(str(folder / f'{file}.jac')), names)
            for spec in specs:
                cls.specs[spec.name], cls.modules[spec.name] = spec, module

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)

    def setUp(self):
        self.runners = {}

    def driver(self, name='GraphSum', actual=None):
        spec = self.specs[name]
        cpu = CpuCsrKernel(spec)
        artifact = self.emit([spec])
        self.assertEqual(artifact.format, 'jac-ptx-csr-v1')
        self.assertEqual(len(artifact.kernels[0]['parameters']), 13)
        self.assertIn('addrspace(1)', artifact.llvm_ir)
        self.assertNotIn('.extern .func', artifact.ptx)
        double = None
        use_cuda = self.on_cuda if actual is None else actual
        if use_cuda:
            session = self.cuda.CudaSession(artifact.ptx, artifact.kernels[0]['name'],
                                           graph_format='csr')
        else:
            double = CsrDriverDouble(cpu.lane, cpu.scalar, artifact.kernels[0]['name'])
            session = self.cuda.CudaSession(artifact.ptx, artifact.kernels[0]['name'],
                                           graph_format='csr', driver=self.cuda.CudaDriver(library=double))
        self.addCleanup(session.close)
        return cpu, double, session

    def execute(self, buffers, name='GraphSum'):
        if name not in self.runners:
            self.runners[name] = self.driver(name)
        cpu, double, session = self.runners[name]
        expected, codes = cpu.run(buffers)
        buffers.results[:] = array(buffers.results.typecode, [-987654]) * len(buffers.heads)
        plan = session.execute(buffers)
        self.assertEqual(bytes(buffers.results), bytes(array(buffers.results.typecode, expected)))
        self.assertEqual(buffers.status.tolist(), codes)
        if double:
            self.assertIsNone(double.callback_error)
            self.assertEqual(double.stack, [0x1234])
        return buffers.results.tolist(), codes, plan

    def buffers(self, values, rows, heads, seeds, name='GraphSum', queue=1024, limit=1000000):
        offsets, targets = flatten(rows)
        return self.memory.csr_buffers(values, offsets, targets, heads, seeds,
                                       self.specs[name].dtype, queue, limit)

    def graph(self, name, values, rows):
        module, spec = self.modules[name], self.specs[name]
        nodes = [getattr(module, spec.node_type)(**{spec.node_field: value}) for value in values]
        for node, row in zip(nodes, rows):
            for target in row:
                self.jac.connect(node, nodes[target], getattr(module, spec.edge_type))
        return nodes

    def reference(self, name, values, rows, heads, seeds):
        nodes = self.graph(name, values, rows)
        spec = self.specs[name]
        results = []
        for head, seed in zip(heads, seeds):
            walker = getattr(self.modules[name], name)(**{spec.state_field: seed})
            if head != -1:
                self.jac.spawn(walker, nodes[head])
            results.append(getattr(walker, spec.state_field))
        return results

    def test_fifo_order_repeated_arrivals_and_shared_object_packing(self):
        name = 'GraphTrace'
        values, rows = [1, 2, 3, 4], [[1, 2], [3], [3], []]
        heads, seeds = [0, 1, 2, 3, -1], [0, 0, 0, 0, 17]
        expected = self.reference(name, values, rows, heads, seeds)
        self.assertEqual(expected, [12344, 24, 34, 4, 17])
        self.assertEqual(self.execute(self.buffers(values, rows, heads, seeds, name, 2, 5), name)[:2],
                         (expected, [0] * 5))
        # The node query deduplicates parallel edges within one visit only.
        nodes = self.graph(name, values, [[1, 2, 1], [3], [3], []])
        walkers = [self.modules[name].GraphTrace(total=seed) for seed in seeds]
        runtime = self.gpu.GpuWalkerRuntime(self.modules[name].GraphTrace, graph_format='csr',
                                           queue_capacity=2, max_visits=5)
        self.addCleanup(runtime.close)
        _, _, runtime.session = self.driver(name)
        starts = [None if head == -1 else nodes[head] for head in heads]
        packed = runtime.prepare(walkers, starts)
        self.assertEqual(len(packed.nodes), 4)
        self.assertEqual(packed.buffers.offsets.tolist(), [0, 2, 3, 4, 4])
        self.assertEqual(packed.buffers.targets.tolist(), [1, 2, 3, 3])
        result = runtime.run_walkers(walkers, starts)
        self.assertEqual(result.values, expected)
        self.assertEqual([w.total for w in walkers], expected)

    def test_random_dags_permutations_and_warp_boundaries(self):
        rng = random.Random(930)
        values = list(range(-11, 12))
        rows = [rng.sample(list(range(i + 1, 23)), min(rng.randrange(3), 22 - i))
                for i in range(23)]
        for count in (0, 1, 31, 32, 33, 257, 1000):
            heads = [rng.randrange(-1, 23) for _ in range(count)]
            seeds = list(range(count))
            expected = self.reference('GraphSum', values, rows, heads, seeds)
            order = list(range(23))
            rng.shuffle(order)
            slots = {old: new for new, old in enumerate(order)}
            buffers = self.buffers([values[old] for old in order],
                                   [[slots[v] for v in rows[old]] for old in order],
                                   [-1 if h == -1 else slots[h] for h in heads], seeds)
            self.assertEqual(self.execute(buffers)[:2], (expected, [0] * count))

    def test_high_degree_empty_rows_and_ring_wrap(self):
        rows = [list(range(1, 514))] + [[] for _ in range(513)]
        values = list(range(514))
        buffers = self.buffers(values, rows, [0, 513, -1], [7, 11, 13], queue=513)
        expected = self.reference('GraphSum', values, rows, [0, 513, -1], [7, 11, 13])
        self.assertEqual(self.execute(buffers)[:2], (expected, [0, 0, 0]))
        rows = [[i + 1] for i in range(100)] + [[]]
        buffers = self.buffers(list(range(101)), rows, [0, 50, -1], [0, 5, 9], queue=1, limit=101)
        self.assertEqual(self.execute(buffers)[:2], ([5050, sum(range(50, 101)) + 5, 9], [0, 0, 0]))
        buffers.max_visits = 100
        self.assertEqual(self.execute(buffers)[1], [2, 0, 0])
        empty = self.buffers([], [], [-1, -1], [7, -9], queue=1)
        self.assertEqual(self.execute(empty)[:2], ([7, -9], [0, 0]))

    def test_bounds_queue_overflow_and_cycles_leave_results_untouched(self):
        for values, rows, heads, queue, limit, code in (
                ([], [], [0], 1, 1, 1),
                ([1], [[]], [-2], 1, 1, 1),
                ([1], [[1]], [0], 1, 2, 1),
                ([1], [[-1]], [0], 1, 2, 1),
                ([1], [[0]], [0], 1, 7, 2),
                ([1, 2], [[1], [0]], [0], 1, 7, 2),
                ([1, 2, 3], [[1, 2], [], []], [0], 1, 10, 6)):
            buffers = self.buffers(values, rows, heads, [0], queue=queue, limit=limit)
            self.assertEqual(self.execute(buffers)[:2], ([-987654], [code]))
        for offsets in ([-1, 0], [1, 0], [0, 1]):
            buffers = self.memory.csr_buffers([1], offsets, [], [0], [0],
                                               self.memory.GpuScalarType.INT64, 1, 1)
            self.assertEqual(self.execute(buffers)[:2], ([-987654], [5]))

    def test_float_integer_and_conditional_bodies(self):
        rows = [[1, 2], [3], [3], []]
        for name, values, seeds in (
                ('ChainSum', [1e16, -1e16, 1.0, 1.0], [0.0, -0.0]),
                ('EvenSum', [2**53 + 2, -3, -2, 4], [0, 9])):
            expected = self.reference(name, values, rows, [0, -1], seeds)
            self.assertEqual(self.execute(self.buffers(values, rows, [0, -1], seeds, name), name)[:2],
                             (expected, [0, 0]))
        for name, values, seeds, codes in (
                ('GraphSum', [1, 1], [2**63 - 1, 0], [3, 0]),
                ('GraphModulo', [7, -(2**63)], [0, -1], [4, 0])):
            buffers = self.buffers(values, [[], []], [0, 1], seeds, name)
            result, status, _ = self.execute(buffers, name)
            self.assertEqual(status, codes)
            self.assertEqual(result[0], -987654)

    def test_publication_failure_refresh_and_empty_batch(self):
        module = self.modules['GraphSum']
        runtime = self.gpu.GpuWalkerRuntime(module.GraphSum, graph_format='csr',
                                           queue_capacity=1, max_visits=3)
        self.addCleanup(runtime.close)
        _, _, runtime.session = self.driver()
        nodes = self.graph('GraphSum', [1, 2, 3, 4], [[1, 2], [], [], []])
        walkers = [module.GraphSum(total=7), module.GraphSum(total=9)]
        for text, starts in (('queue capacity', [nodes[3], nodes[0]]),
                             ('visit limit', [nodes[3], nodes[1]])):
            if text == 'visit limit':
                self.jac.connect(nodes[1], nodes[1], module.Link)
            with self.assertRaisesRegex(RuntimeError, text):
                runtime.run_walkers(walkers, starts)
            self.assertEqual([w.total for w in walkers], [7, 9])
        walkers[1].total = 2**63 - 1
        with self.assertRaises(OverflowError):
            runtime.run_walkers(walkers, [nodes[3], nodes[3]])
        self.assertEqual([w.total for w in walkers], [7, 2**63 - 1])
        walkers[1].total = 9
        self.assertEqual(runtime.run_walkers(walkers, [nodes[3]] * 2).values, [11, 13])
        nodes[3].value = 7
        self.assertEqual(runtime.run_walkers(walkers, [nodes[3]] * 2).values, [18, 20])
        # Topology is repacked between calls as well as node fields.
        self.jac.connect(nodes[3], nodes[2], module.Link)
        self.assertEqual(runtime.run_walkers(walkers, [nodes[3]] * 2).values, [28, 30])
        self.assertFalse(runtime.run_walkers([], []).gpu_executed)
        self.assertFalse(self.gpu.run_walkers([], [], graph_format='csr').gpu_executed)
        for kwargs in ({'queue_capacity': 0}, {'max_visits': -1}, {'queue_capacity': True},
                       {'queue_capacity': 2**63}, {'graph_format': 'invalid'}):
            with self.assertRaises(ValueError):
                self.gpu.run_walkers([], [], **({'graph_format': 'csr'} | kwargs))

    def test_arenas_capacity_alignment_reuse_and_partial_growth_failure(self):
        _, double, session = self.driver(actual=False)
        small = self.buffers([2], [[]], [0], [1], queue=1)
        session.execute(small)
        double.free_bytes = 5000
        large = self.buffers([2] * 65, [[i + 1] for i in range(64)] + [[]],
                              [0] * 65, [1] * 65, queue=17)
        with self.assertRaises(MemoryError):
            session.execute(large)
        self.assertFalse(session.closed)
        plan = session.execute(small)
        self.assertEqual(plan.allocated_bytes(), sum(size for _, size in double.allocations.values()))
        double.free_bytes = 2**30
        plan = session.execute(large)
        allocations = len(double.allocated_sizes)
        session.execute(small)
        self.assertEqual(len(double.allocated_sizes), allocations)
        self.assertEqual(plan.payload_bytes(), 16 * 65 + 8 + 8 * 64 + 28 * 65 + 8 * 65 * 17)
        for layout in (plan.graph_layout, plan.edge_layout, plan.walker_layout, plan.queue_layout):
            self.assertTrue(all(offset % 256 == 0 for offset in layout.offsets))
        self.assertLessEqual(plan.graph_layout.offsets[0] + 8 * plan.graph_layout.capacity,
                             plan.graph_layout.offsets[1])
        self.assertLessEqual(plan.graph_layout.offsets[1] + 8 * (plan.graph_layout.capacity + 1),
                             plan.graph_layout.nbytes)
        session.close()
        self.assertFalse(double.allocations or double.contexts or double.modules)
        self.assertEqual(double.stack, [0x1234])
        self.assertIsNone(double.callback_error)
        _, double, session = self.driver(actual=False)
        session.execute(self.buffers([], [], [-1], [7], queue=1))
        empty_plan = session.execute(self.buffers([], [], [], [], queue=1))
        self.assertEqual(empty_plan.allocated_bytes(),
                         sum(size for _, size in double.allocations.values()))

    def test_cuda_failures_cleanup_all_csr_arenas(self):
        for failure in ('fail_launch', 'fail_sync', 'fail_alloc'):
            _, double, session = self.driver(actual=False)
            setattr(double, failure, True)
            buffers = self.buffers([1, 2], [[1], []], [0], [7])
            with self.assertRaises(self.cuda.CudaError):
                session.execute(buffers)
            self.assertFalse(double.allocations or double.contexts or double.modules)
            self.assertTrue(session.closed)
            self.assertEqual(double.stack, [0x1234])


if __name__ == '__main__':
    unittest.main()
