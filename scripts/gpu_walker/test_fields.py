"""SoA node fields and owned nested data; JAC_GPU_TEST_CUDA=1 runs real PTX."""

from array import array
import ctypes as c
import os
from pathlib import Path
import tempfile
import unittest

from test_runtime import DriverDouble


class FieldKernel:
    def __init__(self, spec, graph_format):
        from jaclang.compiler.backends.native import ptx_walker, ptx_csr
        from jaclang.compiler.backends.native.llvm import binding as llvm

        self.csr = graph_format == 'csr'
        build = ptx_csr.build_csr_module if self.csr else ptx_walker.build_chain_module
        emit = ptx_csr.emit_csr_ptx if self.csr else ptx_walker.emit_chain_ptx
        target = llvm.Target.from_default_triple().create_target_machine(opt=2)
        module = build([spec], target, device=False)
        self.engine = llvm.create_mcjit_compiler(module, target)
        self.engine.finalize_object()
        self.artifact = emit([spec])
        self.fields = len(spec.field_paths())
        self.scalar = c.c_int64 if spec.dtype.value == 'int64' else c.c_double
        self.types = [self.scalar] * self.fields + [c.c_int64] * (3 if self.csr else 2)
        self.types += [self.scalar, self.scalar, c.c_uint32]
        if self.csr:
            self.types.append(c.c_int64)
        self.counts = 5 if self.csr else 2
        symbol = f'jac_{spec.name}_{"csr_" if self.csr else ""}lane'
        self.lane = c.CFUNCTYPE(None, *[c.POINTER(t) for t in self.types],
                               *[c.c_uint64] * (self.counts + 1))(
            self.engine.get_function_address(symbol))

    def run(self, buffers):
        n, m = len(buffers.values), len(buffers.heads)
        inputs = buffers.arrays()[:-2]
        before = [bytes(v) for v in inputs]
        ptrs = [c.cast(v.buffer_info()[0], c.POINTER(t)) for v, t in zip(inputs, self.types)]
        output = (self.scalar * (m + 2))(*([-987654] * (m + 2)))
        status = (c.c_uint32 * (m + 2))(*([173] * (m + 2)))
        ptrs += [c.cast(c.byref(output, 8), c.POINTER(self.scalar)),
                 c.cast(c.byref(status, 4), c.POINTER(c.c_uint32))]
        if self.csr:
            scratch = (c.c_int64 * (m * buffers.queue_capacity + 2))()
            scratch[0] = scratch[-1] = -713
            ptrs.append(c.cast(c.byref(scratch, 8), c.POINTER(c.c_int64)))
            counts = [n, len(buffers.targets), m, buffers.queue_capacity, buffers.max_visits]
        else:
            counts = [n, m]
        for lane in reversed(range(m)):
            self.lane(*ptrs, *counts, lane)
        for lane in (m, 2**32, 2**64 - 1):
            self.lane(*([None] * len(self.types)), *counts, lane)
        assert output[0] == output[-1] == -987654
        assert status[0] == status[-1] == 173
        assert before == [bytes(v) for v in inputs]
        if self.csr:
            assert scratch[0] == scratch[-1] == -713
        return list(output)[1:-1], list(status)[1:-1]


class FieldDriver(DriverDouble):
    def __init__(self, kernel):
        self.kernel = kernel
        super().__init__(kernel.lane, kernel.scalar, kernel.artifact.kernels[0]['name'])

    def launch(self, function, gx, gy, gz, bx, by, bz, shared, stream, params, extra):
        if self.fail_launch:
            return 700
        count = len(self.kernel.types)
        args = [c.cast(params[i], c.POINTER(c.c_uint64))[0]
                for i in range(count + self.kernel.counts)]
        assert all(address % 256 == 0 for address in args[:count] if address)
        assert (gy, gz, by, bz, shared, stream, bool(extra)) == (1, 1, 1, 1, 0, None, False)
        for address in args[:count]:
            if address:
                assert any(base <= address <= base + size
                           for base, (_, size) in self.allocations.items())
        ptrs = [c.cast(address, c.POINTER(t))
                for address, t in zip(args[:count], self.kernel.types)]
        for lane in reversed(range(gx * bx)):
            self.lane(*ptrs, *args[count:], lane)
        self.launches.append((gx, bx, *args[count:]))
        return 0


class NodeFieldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from jaclang.runtime.runtime import JacRuntime
        from jaclang.runtime.context import ExecutionContext
        from jaclang.runtime import gpu, gpu_cuda, gpu_memory
        from jaclang.compiler.backends.native.ptx import compile_ptx_frontend, PtxUnsupported
        from jaclang.compiler.backends.native.ptx_walker import select_chain_walkers
        from jaclang.compiler.backends.native.llvm import binding as llvm

        llvm.initialize_all_targets()
        llvm.initialize_all_asmprinters()
        cls.jac, cls.gpu, cls.cuda, cls.memory = JacRuntime, gpu, gpu_cuda, gpu_memory
        cls.compile = staticmethod(compile_ptx_frontend)
        cls.select = staticmethod(select_chain_walkers)
        cls.unsupported = PtxUnsupported
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
        cls.temp = tempfile.TemporaryDirectory(prefix='jac_gpu_fields_')
        cls.folder = Path(cls.temp.name)
        repo = Path(__file__).resolve().parents[2]
        source = repo / 'jac/examples/gpu/multi_field.jac'
        cls.source = source.read_text()
        cls.modules, cls.specs = {}, {}
        float_source = cls.source.replace(': int', ': float').replace('= 0;', '= 0.0;').replace('>= 0', '>= 0.0')
        deep_source = cls.source.replace('node Sample', 'obj Frame { has pos: Position; }\nnode Sample')
        deep_source = deep_source.replace('position: Position', 'frame: Frame').replace('here.position.', 'here.frame.pos.')
        flat_source = cls.source.replace('position: Position', 'x: int, y: int').replace('here.position.', 'here.')
        for name, path, text in [('nested', source, cls.source),
                                 ('floating', cls.folder / 'floating.jac', float_source),
                                 ('deep', cls.folder / 'deep.jac', deep_source),
                                 ('flat', cls.folder / 'flat.jac', flat_source)]:
            if name != 'nested':
                path.write_text(text)
            cls.modules[name] = JacRuntime.jac_import(target=path.stem, base_path=str(path.parent))[0]
            cls.specs[name] = select_chain_walkers(compile_ptx_frontend(str(path)), ['WeightedSum'])[0]

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)
            cls.temp.cleanup()

    def runtime(self, kind='nested', graph_format='csr', actual=None):
        kernel = FieldKernel(self.specs[kind], graph_format)
        use_cuda = self.on_cuda if actual is None else actual
        double = None if use_cuda else FieldDriver(kernel)
        session = self.cuda.CudaSession(
            kernel.artifact.ptx, kernel.artifact.kernels[0]['name'], graph_format=graph_format,
            node_field_count=kernel.fields,
            driver=None if use_cuda else self.cuda.CudaDriver(library=double))
        self.addCleanup(session.close)
        runtime = self.gpu.GpuWalkerRuntime(self.modules[kind].WeightedSum, graph_format=graph_format,
                                           queue_capacity=32, max_visits=10000)
        self.addCleanup(runtime.close)
        runtime.session = session
        self.assertEqual(kernel.artifact.format, f'jac-ptx-{graph_format}-v2')
        self.assertEqual([p['field_path'] for p in kernel.artifact.kernels[0]['parameters'][:4]],
                         self.specs[kind].field_paths())
        return runtime, kernel, double

    def graph(self, kind, rows):
        module = self.modules[kind]
        scalar = float if kind == 'floating' else int
        nodes = []
        for i in range(len(rows)):
            x, y = scalar(-i if i % 3 == 1 else i), scalar(i * 11 + 7)
            attrs = dict(value=scalar(i + 2), weight=scalar(i % 4 + 1))
            if kind == 'flat':
                attrs.update(x=x, y=y)
            else:
                position = module.Position(x=x, y=y)
                attrs.update(frame=module.Frame(pos=position)) if kind == 'deep' else attrs.update(position=position)
            nodes.append(module.Sample(**attrs))
        for node, row in zip(nodes, rows):
            for target in row:
                self.jac.connect(node, nodes[target], module.Link)
        return nodes

    def walkers(self, kind, count):
        return [self.modules[kind].WeightedSum(total=float(i) if kind == 'floating' else i)
                for i in range(count)]

    def reference(self, kind, starts, walkers):
        result = []
        for start, original in zip(starts, walkers):
            walker = self.modules[kind].WeightedSum(total=original.total)
            if start is not None:
                self.jac.spawn(walker, start)
            result.append(walker.total)
        return result

    def test_flat_nested_float_and_deep_fields_match_serial_jac(self):
        for kind in self.modules:
            for graph_format, rows in [('chain', [[1], [2], [3], []]),
                                       ('csr', [[1, 2], [3], [3], []])]:
                with self.subTest(kind=kind, graph_format=graph_format):
                    runtime, kernel, double = self.runtime(kind, graph_format)
                    nodes = self.graph(kind, rows)
                    for count in (0, 1, 31, 32, 33, 257, 1000):
                        walkers = self.walkers(kind, count)
                        starts = [(nodes + [None])[i % 5] for i in range(count)]
                        expected = self.reference(kind, starts, walkers)
                        packed = runtime.prepare(walkers, starts)
                        cpu, codes = kernel.run(packed.buffers)
                        self.assertEqual(cpu, expected)
                        self.assertEqual(codes, [0] * count)
                        actual = runtime.run_walkers(walkers, starts)
                        self.assertEqual(actual.values, expected)
                        self.assertEqual([w.total for w in walkers], expected)
                        self.assertEqual(actual.memory.node_field_count, 4)
                    walkers = self.walkers(kind, 2)
                    empty = runtime.prepare(walkers, [None, None])
                    self.assertEqual(kernel.run(empty.buffers), ([0, 1], [0, 0]))
                    self.assertEqual(runtime.run_walkers(walkers, [None, None]).values, [0, 1])
                    if double:
                        self.assertIsNone(double.callback_error)

    def test_columns_follow_the_same_node_permutation(self):
        runtime, kernel, _ = self.runtime()
        rows = [[1, 2], [3], [3, 4], [4], []]
        nodes = self.graph('nested', rows)
        walkers = self.walkers('nested', 33)
        starts = [nodes[i % 5] for i in range(33)]
        expected = self.reference('nested', starts, walkers)
        batch = runtime.prepare(walkers, starts)
        self.assertEqual(runtime.schema.field_paths(), ['value', 'weight', 'position.x', 'position.y'])
        columns = batch.buffers.columns()
        for column, path in zip(columns, runtime.schema.field_paths()):
            values = []
            for node in batch.nodes:
                value = node
                for part in path.split('.'):
                    value = getattr(value, part)
                values.append(value)
            self.assertEqual(column.tolist(), values)
        order = [4, 2, 0, 3, 1]
        slots = {old: new for new, old in enumerate(order)}
        offsets, targets = [0], []
        for old in order:
            targets.extend(slots[x] for x in rows[old])
            offsets.append(len(targets))
        permuted = [[column[old] for old in order] for column in columns]
        buffers = self.memory.csr_buffers(permuted[0], offsets, targets,
                                         [slots[h] for h in batch.buffers.heads],
                                         batch.buffers.initial, runtime.schema.dtype,
                                         extra_values=permuted[1:])
        self.assertEqual(kernel.run(buffers), (expected, [0] * len(walkers)))
        runtime.session.execute(buffers)
        self.assertEqual(buffers.results.tolist(), expected)
        self.assertFalse(any(buffers.status))

    def test_cross_node_ownership_and_exact_nested_types(self):
        for kind in ('nested', 'deep'):
            runtime = self.gpu.GpuWalkerRuntime(self.modules[kind].WeightedSum, graph_format='csr')
            self.addCleanup(runtime.close)
            nodes = self.graph(kind, [[], []])
            walkers = self.walkers(kind, 2)
            self.assertEqual(len(runtime.prepare(walkers, nodes).nodes), 2)
            if kind == 'nested':
                nodes[1].position = nodes[0].position
            else:
                nodes[1].frame.pos = nodes[0].frame.pos
            with self.assertRaisesRegex(ValueError, 'shared by different nodes'):
                runtime.run_walkers(walkers, nodes)
            self.assertIsNone(runtime.session)
            self.assertEqual([w.total for w in walkers], [0, 1])
            # Many walkers may still share one node and all its owned data.
            self.assertEqual(len(runtime.prepare(walkers, [nodes[0]] * 2).nodes), 1)
            if kind == 'nested':
                nodes[0].position = None
            else:
                nodes[0].frame.pos = None
            with self.assertRaisesRegex(TypeError, 'exactly type'):
                runtime.prepare(walkers, [nodes[0]] * 2)

    def test_all_columns_refresh_and_arenas_grow_without_reallocation_on_reuse(self):
        runtime, _, double = self.runtime(actual=False)
        for count in (1, 2, 33, 3, 65, 0):
            nodes = self.graph('nested', [[i + 1] if i + 1 < count else [] for i in range(count)])
            walkers = self.walkers('nested', 2)
            starts = [nodes[0] if nodes else None] * 2
            for change in (0, 1):
                for node in nodes:
                    node.value += change
                    node.weight += change
                    node.position.x = 0
                    node.position.y += change * 100
                expected = self.reference('nested', starts, walkers)
                allocations = len(double.allocated_sizes)
                result = runtime.run_walkers(walkers, starts)
                self.assertEqual(result.values, expected)
                self.assertEqual(result.memory.payload_bytes(), 40 * count + 8 + 8 * max(0, count - 1) + 28 * 2 + 8 * 32 * 2)
                self.assertTrue(all(offset % 256 == 0 for offset in result.memory.graph_layout.offsets))
                self.assertEqual(result.memory.allocated_bytes(), sum(size for _, size in double.allocations.values()))
                if change:
                    self.assertEqual(len(double.allocated_sizes), allocations)
        runtime.close()
        self.assertFalse(double.allocations)
        self.assertFalse(double.contexts)

    def test_nonfirst_field_overflow_and_lazy_branches_preserve_batch(self):
        runtime, kernel, _ = self.runtime()
        nodes = self.graph('nested', [[], []])
        nodes[0].value, nodes[0].weight, nodes[0].position.y = 2, 2**62, 0
        nodes[0].position.x = -1
        nodes[1].position.y = 2**53 + 3
        walkers = self.walkers('nested', 2)
        expected = self.reference('nested', nodes, walkers)
        self.assertEqual(runtime.run_walkers(walkers, nodes).values, expected)
        saved = [w.total for w in walkers]
        nodes[0].position.x = 0
        packed = runtime.prepare(walkers, nodes)
        self.assertEqual(kernel.run(packed.buffers)[1], [3, 0])
        with self.assertRaises(OverflowError):
            runtime.run_walkers(walkers, nodes)
        self.assertEqual([w.total for w in walkers], saved)
        nodes[0].weight = True
        with self.assertRaises(TypeError):
            runtime.prepare(walkers, nodes)
        nodes[0].weight = 2**63
        with self.assertRaises(OverflowError):
            runtime.prepare(walkers, nodes)

    def test_column_shape_and_kernel_abi_mismatch_fail_before_launch(self):
        runtime, _, double = self.runtime(actual=False)
        nodes = self.graph('nested', [[]])
        batch = runtime.prepare(self.walkers('nested', 1), nodes)
        buffers = batch.buffers
        self.assertEqual(len(double.launches), 0)
        buffers.extra_values.pop()
        with self.assertRaisesRegex(ValueError, 'field count'):
            runtime.session.execute(buffers)
        buffers.extra_values.append(array('q', []))
        with self.assertRaisesRegex(ValueError, 'matching lengths'):
            runtime.session.execute(buffers)
        buffers.extra_values[-1] = array('d', [1.0])
        with self.assertRaisesRegex(ValueError, 'scalar types'):
            runtime.session.execute(buffers)
        self.assertEqual(len(double.launches), 0)
        with self.assertRaises(ValueError):
            self.memory.csr_buffers([1], [0, 0], [], [0], [0], extra_values=[[1, 2]])
        with self.assertRaises(ValueError):
            self.memory.chain_buffers([1], [-1], [0], [0], extra_values=[[]])
        for count in (0, -1, True):
            with self.assertRaises(ValueError):
                self.memory.csr_memory_plan(1, 0, 1, 1, node_field_count=count)

    def test_unsupported_nested_schemas_are_diagnosed(self):
        variants = {
            'mixed': self.source.replace('weight: int', 'weight: float'),
            'recursive': self.source.replace('y: int;', 'y: int, parent: Position;'),
            'list': self.source.replace('y: int;', 'y: int, items: list[int];'),
            'optional': self.source.replace('position: Position', 'position: Position | None'),
            'method': self.source.replace('y: int;', 'y: int; def extra -> int { return self.x; }'),
            'node_ref': self.source.replace('y: int;', 'y: int, other: Sample;'),
        }
        for name, source in variants.items():
            with self.subTest(name=name):
                self.assertNotEqual(source, self.source)
                path = self.folder / f'reject_{name}.jac'
                path.write_text(source)
                with self.assertRaises(self.unsupported):
                    self.select(self.compile(str(path)), ['WeightedSum'])

    def test_empty_graph_and_failed_launch_clean_up_all_field_storage(self):
        runtime, _, double = self.runtime(actual=False)
        empty = runtime.run_walkers(self.walkers('nested', 2), [None, None])
        self.assertEqual(empty.values, [0, 1])
        nodes = self.graph('nested', [[1], []])
        walkers = self.walkers('nested', 2)
        double.fail_sync = True
        with self.assertRaises(self.cuda.CudaError):
            runtime.run_walkers(walkers, nodes)
        self.assertEqual([w.total for w in walkers], [0, 1])
        self.assertFalse(double.allocations)
        self.assertFalse(double.contexts)


if __name__ == '__main__':
    unittest.main()
