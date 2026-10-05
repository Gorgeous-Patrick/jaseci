"""Multiple private walker columns; JAC_GPU_TEST_CUDA=1 executes real PTX."""

from array import array
import copy
import os
from pathlib import Path
import tempfile
import unittest

from test_fields import FieldKernel, FieldDriver


class WalkerFieldTests(unittest.TestCase):
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
        cls.compile, cls.select = staticmethod(compile_ptx_frontend), staticmethod(select_chain_walkers)
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
        cls.temp = tempfile.TemporaryDirectory(prefix='jac_gpu_states_')
        cls.folder = Path(cls.temp.name)
        source = Path(__file__).resolve().parents[2] / 'jac/examples/gpu/walker_fields.jac'
        cls.source = source.read_text()
        floating = cls.source.replace(': int', ': float').replace('= 0', '= 0.0')
        floating = floating.replace('+= 1;', '+= 1.0;').replace('== -1', '== -1.0')
        deep = cls.source.replace('node Sample', 'obj Frame { has data: Metrics; }\nnode Sample')
        deep = deep.replace('metrics: Metrics = Metrics()', 'frame: Frame = Frame(data=Metrics())')
        deep = deep.replace('self.metrics.', 'self.frame.data.')
        flat = cls.source.replace('metrics: Metrics = Metrics()', 'weighted: int = 0, last: int = 0')
        flat = flat.replace('self.metrics.', 'self.')
        single_node = cls.source.replace('value: int,\n        weight: int;', 'value: int;')
        single_node = single_node.replace('here.weight', 'here.value')
        # A node and walker can have the same declared data type, but not the same instance.
        shared = cls.source.replace('weight: int;', 'weight: int, data: Metrics;')
        alias = cls.source.replace('metrics: Metrics = Metrics()',
                                   'metrics: Metrics = Metrics(), other: Metrics = Metrics()')
        no_else = cls.source.replace('visit [->:Link:->];',
                                    'if self.count > 2 { self.total += self.metrics.last; '
                                    'if self.total > 0 { self.count += 1; } }\nvisit [->:Link:->];')
        modulo = cls.source.replace('self.metrics.last = self.metrics.weighted - self.count;',
                                   'self.metrics.last = self.metrics.weighted % self.count;')
        cls.modules, cls.specs = {}, {}
        for kind, text in dict(nested=cls.source, floating=floating, deep=deep, flat=flat,
                               shared=shared, alias=alias, no_else=no_else, modulo=modulo,
                               single_node=single_node).items():
            path = source if kind == 'nested' else cls.folder / f'state_{kind}.jac'
            if kind != 'nested':
                path.write_text(text)
            cls.modules[kind] = JacRuntime.jac_import(target=path.stem, base_path=str(path.parent))[0]
            cls.specs[kind] = select_chain_walkers(compile_ptx_frontend(str(path)), ['Statistics'])[0]

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
            node_field_count=kernel.fields, state_field_count=kernel.states,
            driver=None if use_cuda else self.cuda.CudaDriver(library=double))
        self.addCleanup(session.close)
        runtime = self.gpu.GpuWalkerRuntime(self.modules[kind].Statistics, graph_format=graph_format,
                                           queue_capacity=16, max_visits=10000)
        self.addCleanup(runtime.close)
        runtime.session = session
        self.assertEqual(kernel.artifact.format, f'jac-ptx-{graph_format}-v3')
        return runtime, kernel, double

    def graph(self, kind, rows):
        module = self.modules[kind]
        scalar = float if kind == 'floating' else int
        nodes = [module.Sample(value=scalar(i - 2),
                               **({} if kind == 'single_node' else {'weight': scalar(i + 1)}),
                               **({'data': module.Metrics()} if kind == 'shared' else {}))
                 for i in range(len(rows))]
        for node, row in zip(nodes, rows):
            for target in row:
                self.jac.connect(node, nodes[target], module.Link)
        return nodes

    def walkers(self, kind, count):
        module = self.modules[kind]
        scalar = float if kind == 'floating' else int
        result = []
        for i in range(count):
            metrics = dict(weighted=scalar(i * 3), last=scalar(-i))
            if kind == 'flat':
                fields = metrics
            elif kind == 'deep':
                fields = dict(frame=module.Frame(data=module.Metrics(**metrics)))
            else:
                fields = dict(metrics=module.Metrics(**metrics))
                if kind == 'alias':
                    fields['other'] = module.Metrics()
            result.append(module.Statistics(total=scalar(i), count=scalar(i % 3), **fields))
        return result

    def snapshot(self, kind, walkers):
        fields = {}
        for path in self.specs[kind].state_paths():
            column = []
            for walker in walkers:
                value = walker
                for part in path.split('.'):
                    value = getattr(value, part)
                column.append(value)
            fields[path] = column
        return fields

    def reference(self, kind, starts, walkers):
        # Recreate Jac walkers; deepcopying their traversal anchors is unnecessary.
        copies = []
        for walker, start in zip(walkers, starts):
            fields = {name: copy.deepcopy(value) for name, value in vars(walker).items()
                      if name in ('total', 'count', 'weighted', 'last', 'metrics', 'frame', 'other')}
            reference = self.modules[kind].Statistics(**fields)
            if start is not None:
                self.jac.spawn(reference, start)
            copies.append(reference)
        return self.snapshot(kind, copies)

    def test_all_state_columns_match_serial_sequential_branches_and_fifo(self):
        for kind in ('nested', 'floating', 'flat', 'deep', 'no_else', 'alias', 'single_node'):
            for graph_format in ('chain', 'csr'):
                with self.subTest(kind=kind, graph_format=graph_format):
                    runtime, kernel, double = self.runtime(kind, graph_format)
                    rows = [[1], [2], [3], []] if graph_format == 'chain' else [[1, 2], [3], [3], []]
                    nodes = self.graph(kind, rows)
                    for count in (0, 1, 31, 32, 33, 257, 1000):
                        walkers = self.walkers(kind, count)
                        starts = [(nodes + [None])[i % 5] for i in range(count)]
                        expected = self.reference(kind, starts, walkers)
                        batch = runtime.prepare(walkers, starts)
                        self.assertEqual([c.tolist() for c in batch.buffers.initial_columns()],
                                         list(self.snapshot(kind, walkers).values()))
                        self.assertEqual(kernel.run_states(batch.buffers), (list(expected.values()), [0] * count))
                        actual = runtime.run_walkers(walkers, starts)
                        self.assertEqual(actual.fields, expected)
                        self.assertEqual(actual.values, expected['total'])
                        self.assertEqual(self.snapshot(kind, walkers), expected)
                    if double:
                        self.assertIsNone(double.callback_error)

    def test_memory_metadata_refresh_and_capacity_reuse(self):
        for graph_format in ('chain', 'csr'):
            runtime, kernel, double = self.runtime(graph_format=graph_format, actual=False)
            metadata = kernel.artifact.kernels[0]
            self.assertEqual(metadata['state_fields'], ['total', 'count', 'metrics.weighted', 'metrics.last'])
            self.assertEqual(metadata['default_initial_states'], [0, 0, None, None])
            pointers = [p for p in metadata['parameters'] if p.get('length') == 'walker_count' and 'field_path' in p]
            self.assertEqual([p['field_path'] for p in pointers], metadata['state_fields'] * 2)
            nodes = self.graph('nested', [[1], []])
            for count in (1, 33, 2, 65, 0):
                walkers = self.walkers('nested', count)
                starts = [nodes[0]] * count
                for repetition in range(2):
                    for w in walkers:
                        w.metrics.last += 17
                        w.count += 2
                    expected = self.reference('nested', starts, walkers)
                    allocations = len(double.allocated_sizes)
                    result = runtime.run_walkers(walkers, starts)
                    self.assertEqual(result.fields, expected)
                    plan = result.memory
                    self.assertEqual(plan.state_field_count, 4)
                    payload = (48 if count else 0) + 76 * count
                    if graph_format == 'csr':
                        payload += 8 + (8 if count else 0) + 8 * 16 * count
                    self.assertEqual(plan.payload_bytes(), payload)
                    self.assertTrue(all(offset % 256 == 0 for offset in plan.walker_layout.offsets))
                    self.assertEqual(plan.allocated_bytes(), sum(size for _, size in double.allocations.values()))
                    if repetition:
                        self.assertEqual(len(double.allocated_sizes), allocations)
            runtime.close()
            self.assertFalse(double.allocations)
            self.assertFalse(double.contexts)

    def test_late_arithmetic_errors_leave_every_result_and_host_field_untouched(self):
        for graph_format in ('chain', 'csr'):
            for kind, error, status in [('nested', OverflowError, 3), ('modulo', ZeroDivisionError, 4)]:
                runtime, kernel, _ = self.runtime(kind, graph_format)
                nodes = self.graph(kind, [[], []])
                nodes[0].value = 2
                nodes[0].weight = 2**62 if kind == 'nested' else 1
                walkers = self.walkers(kind, 2)
                if kind == 'modulo':
                    walkers[0].count = -1
                before = self.snapshot(kind, walkers)
                batch = runtime.prepare(walkers, nodes)
                cpu, codes = kernel.run_states(batch.buffers)
                self.assertEqual(codes, [status, 0])
                self.assertEqual([column[0] for column in cpu], [-987654] * 4)
                for column in batch.buffers.result_columns():
                    column[:] = array('q', [-987654] * 2)
                runtime.session.execute(batch.buffers)
                self.assertEqual([column.tolist() for column in batch.buffers.result_columns()], cpu)
                with self.assertRaises(error):
                    runtime.run_walkers(walkers, nodes)
                self.assertEqual(self.snapshot(kind, walkers), before)
                nodes[0].value = -2  # The overflowing multiplication/modulo branch is now skipped.
                expected = self.reference(kind, nodes, walkers)
                self.assertEqual(runtime.run_walkers(walkers, nodes).fields, expected)

    def test_mutable_nested_aliases_and_wrong_types_are_rejected_before_cuda(self):
        for kind in ('nested', 'deep', 'shared', 'alias'):
            runtime = self.gpu.GpuWalkerRuntime(self.modules[kind].Statistics, graph_format='csr')
            self.addCleanup(runtime.close)
            nodes = self.graph(kind, [[], []])
            walkers = self.walkers(kind, 2)
            runtime.prepare(walkers, nodes)
            if kind == 'deep':
                walkers[1].frame.data = walkers[0].frame.data
            elif kind == 'shared':
                nodes[1].data = walkers[0].metrics
            elif kind == 'alias':
                walkers[0].other = walkers[0].metrics
            else:
                walkers[1].metrics = walkers[0].metrics
            with self.assertRaisesRegex(ValueError, 'one state path|node and walker'):
                runtime.run_walkers(walkers, nodes)
            self.assertIsNone(runtime.session)
        runtime = self.gpu.GpuWalkerRuntime(self.modules['nested'].Statistics)
        self.addCleanup(runtime.close)
        for value, error in [(None, TypeError), (True, TypeError), (2**63, OverflowError)]:
            walkers = self.walkers('nested', 1)
            if value is None:
                walkers[0].metrics = value
            else:
                walkers[0].metrics.last = value
            with self.assertRaises(error):
                runtime.prepare(walkers, [None])

    def test_changed_host_leaf_or_nested_identity_prevents_all_publication(self):
        for replace_object in (False, True):
            runtime, _, double = self.runtime(actual=False)
            walkers = self.walkers('nested', 2)
            nodes = self.graph('nested', [[], []])
            before = self.snapshot('nested', walkers)
            if replace_object:
                old = walkers[1].metrics
                double.on_sync = lambda: setattr(walkers[1], 'metrics', self.modules['nested'].Metrics(
                    weighted=old.weighted, last=old.last))
            else:
                double.on_sync = lambda: setattr(walkers[1].metrics, 'last', 99)
                before['metrics.last'][1] = 99
            with self.assertRaisesRegex(RuntimeError, 'changed during the GPU call'):
                runtime.run_walkers(walkers, nodes)
            self.assertEqual(self.snapshot('nested', walkers), before)

    def test_state_column_shape_and_abi_checks_precede_launch(self):
        runtime, _, double = self.runtime(actual=False)
        batch = runtime.prepare(self.walkers('nested', 2), [None, None])
        buffers = batch.buffers
        saved = buffers.extra_initial.pop()
        with self.assertRaisesRegex(ValueError, 'state field count'):
            runtime.session.execute(buffers)
        buffers.extra_initial.append(saved)
        for bad in [array('q', []), array('d', [0, 0])]:
            buffers.extra_results[-1] = bad
            with self.assertRaisesRegex(ValueError, 'state columns'):
                runtime.session.execute(buffers)
        self.assertFalse(double.launches)
        for count in (0, -1, True):
            with self.assertRaises(ValueError):
                self.memory.memory_plan(1, 1, state_field_count=count)
            with self.assertRaises(ValueError):
                self.memory.csr_memory_plan(1, 0, 1, 1, state_field_count=count)
        with self.assertRaises(ValueError):
            self.memory.chain_buffers([1], [-1], [0], [0], extra_initial=[[]])
        with self.assertRaises(ValueError):
            self.memory.csr_buffers([1], [0, 0], [], [0], [0], extra_initial=[[]])

    def test_unsupported_state_schemas_and_effects_are_diagnosed(self):
        variants = {
            'mixed': self.source.replace('count: int = 0', 'count: float = 0.0'),
            'missing_default': self.source.replace('count: int = 0', 'count: int'),
            'recursive': self.source.replace('last: int = 0;', 'last: int = 0, child: Metrics | None = None;'),
            'container': self.source.replace('last: int = 0;', 'last: int = 0, items: list[int] = [];'),
            'replace_object': self.source.replace('self.count += 1;', 'self.metrics = Metrics();'),
            'node_write': self.source.replace('self.count += 1;', 'here.value += 1;'),
            'branch_local': self.source.replace('self.count += 1;', 'if True { x = self.count; }'),
        }
        for name, text in variants.items():
            self.assertNotEqual(text, self.source)
            path = self.folder / f'reject_{name}.jac'
            path.write_text(text)
            with self.subTest(name=name), self.assertRaises(self.unsupported):
                self.select(self.compile(str(path)), ['Statistics'])

    def test_empty_traversals_preserve_all_fields_and_driver_failure_cleans_up(self):
        for graph_format in ('chain', 'csr'):
            runtime, kernel, double = self.runtime(graph_format=graph_format, actual=False)
            walkers = self.walkers('nested', 33)
            before = self.snapshot('nested', walkers)
            packed = runtime.prepare(walkers, [None] * len(walkers))
            self.assertEqual(kernel.run_states(packed.buffers), (list(before.values()), [0] * len(walkers)))
            self.assertEqual(runtime.run_walkers(walkers, [None] * len(walkers)).fields, before)
            double.fail_sync = True
            nodes = self.graph('nested', [[]])
            with self.assertRaises(self.cuda.CudaError):
                runtime.run_walkers(walkers, nodes * len(walkers))
            self.assertEqual(self.snapshot('nested', walkers), before)
            self.assertFalse(double.allocations)
            self.assertFalse(double.contexts)


if __name__ == '__main__':
    unittest.main()
