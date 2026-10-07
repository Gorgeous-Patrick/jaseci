"""Named GPU cursors: real Jac CPU differential, LLVM JIT and optional CUDA."""
from pathlib import Path
import os
import random
import tempfile
import unittest

class NamedGpuTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        from jaclang.runtime.runtime import JacRuntime
        from jaclang.runtime.context import ExecutionContext
        from jaclang.runtime import gpu
        from jaclang.runtime import gpu_cursors as multi
        from jaclang.compiler.backends.native.ptx import compile_ptx_frontend, PtxUnsupported
        from jaclang.compiler.backends.native.ptx_walker import select_chain_walkers
        from jaclang.compiler.backends.native.llvm import binding as llvm
        llvm.initialize_all_targets()
        llvm.initialize_all_asmprinters()
        cls.jac, cls.gpu, cls.multi = (JacRuntime, gpu, multi)
        base, target = (JacRuntime.get_base_path_dir(), JacRuntime.get_full_target_path())
        try:
            JacRuntime.set_base_path(None)
            JacRuntime.set_full_target_path(None)
            cls.context = ExecutionContext()
        finally:
            JacRuntime.set_base_path(base)
            JacRuntime.set_full_target_path(target)
        cls.token = JacRuntime.push_request_context(cls.context)
        path = Path(__file__).resolve().parents[2] / 'jac/examples/gpu/named_cursors.jac'
        cls.module = JacRuntime.jac_import(target=path.stem, base_path=str(path.parent))[0]
        cls.frontend, cls.select, cls.unsupported = (staticmethod(compile_ptx_frontend), staticmethod(select_chain_walkers), PtxUnsupported)
        cls.specs = {s.name: s for s in select_chain_walkers(compile_ptx_frontend(str(path)), ['Dot', 'Three', 'Conditional', 'StopOne', 'LoopDot', 'ReportDot'])}
        cls.schemas = {n: gpu.walker_schema(getattr(cls.module, n), 'csr') for n in cls.specs}
        cls.tmp = tempfile.TemporaryDirectory(prefix='jac-multi-gpu-')

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)
            cls.tmp.cleanup()

    def chain(self, values, edge):
        nodes = [self.module.Scalar(value=v) for v in values]
        for a, b in zip(nodes, nodes[1:]):
            self.jac.connect(a, b, edge)
        return nodes

    def check_batch(self, name, starts, *, capacity=64, limit=1000, layouts=('current', 'predicted', 'random')):
        typ = getattr(self.module, name)
        expected = []
        reports = []
        for binding in starts:
            w = self.jac.spawn(binding, typ())
            expected.append(w.total)
            reports.append(w.reports)
        for layout in layouts:
            walkers = [typ() for _ in starts]
            batch = self.multi.pack_cursors(self.schemas[name], walkers, starts, capacity, limit, layout=layout)
            values, status = self.multi.run_jit(self.specs[name], batch.buffers)
            self.assertEqual(status, [0] * len(starts))
            self.assertEqual(values[0], expected)
            result = self.gpu.publish_results(self.schemas[name], batch, batch.memory_plan(), 'HOST JIT', 0)
            self.assertEqual([w.total for w in walkers], expected)
            self.assertEqual(result.reports, reports)
            if os.environ.get('JAC_GPU_TEST_CUDA') == '1':
                batch = self.multi.pack_cursors(self.schemas[name], [typ() for _ in starts], starts, capacity, limit, layout=layout)
                from jaclang.runtime.gpu_cuda import CudaSession
                session = CudaSession(self.schemas[name].ptx, self.schemas[name].kernel_name, graph_format='csr', node_field_count=len(self.schemas[name].field_paths()), state_field_count=len(self.schemas[name].state_paths()), emits_reports=self.schemas[name].emits_reports, node_dtypes=self.schemas[name].node_types(), state_dtypes=self.schemas[name].state_types(), tagged_reports=self.schemas[name].tagged_reports)
                try:
                    plan = session.execute(batch.buffers)
                    result = self.gpu.publish_results(self.schemas[name], batch, plan, session.gpu_name, session.driver_version)
                finally:
                    session.close()
                self.assertEqual(result.values, expected)
                self.assertEqual(result.reports, reports)
        return batch

    def test_dot_lengths_empty_duplicate_initial_events(self):
        left = self.chain([2, 3, 5], self.module.RowNext)
        right = self.chain([7, 11], self.module.ColumnNext)
        self.check_batch('Dot', [{'a': left[0], 'b': right[0]}, {'a': None, 'b': right[0]}, {'a': left, 'b': [right[0], right[0]]}, {'a': [], 'b': []}, {'a': [left[-1], left[-1]], 'b': [right[-1], right[-1]]}])
        self.check_batch('Dot', [])

    def test_three_cursors_shared_nodes(self):
        nodes = [self.module.Scalar(value=i + 1) for i in range(4)]
        for edge in (self.module.RowNext, self.module.ColumnNext, self.module.ThirdNext):
            for a, b in zip(nodes, nodes[1:]):
                self.jac.connect(a, b, edge)
        batch = self.check_batch('Three', [dict(a=nodes[0], b=nodes[0], c=nodes[0]), dict(a=nodes[1], b=nodes[2], c=nodes[0])])
        self.assertEqual(len(batch.nodes), 4)
        self.assertEqual(len(batch.buffers.queue), 3 * 64 * 2)

    def test_fifo_branch_convergence_repeated_arrivals(self):
        a, b, c, d = [self.module.Scalar(value=v) for v in [1, 2, 3, 4]]
        for x, y in [(a, b), (a, c), (b, d), (c, d)]:
            self.jac.connect(x, y, self.module.RowNext)
        right = [self.module.Scalar(value=v) for v in [5, 6, 7, 8, 9]]
        batch = self.check_batch('Dot', [{'a': a, 'b': right}])
        self.assertEqual(batch.walkers[0].total, 1 * 5 + 2 * 6 + 3 * 7 + 4 * 8 + 4 * 9)
        self.assertEqual(len(batch.nodes), 9)

    def test_mismatch_no_scan_no_visit_and_conditionals(self):
        left = self.chain([2, -1, 5], self.module.RowNext)
        right = self.chain([3, 4, 7], self.module.ColumnNext)
        other = self.module.Other(value=99)
        self.check_batch('Dot', [{'a': [other, left[0]], 'b': [right[0], right[0]]}, {'a': other, 'b': right[0]}])
        self.check_batch('StopOne', [{'a': left[0], 'b': right[:2]}, {'a': left[0], 'b': right[0]}])
        batch = self.check_batch('Conditional', [{'a': left[0], 'b': right[0]}])
        self.assertTrue(batch.buffers.prediction['conditional_conservative'])
        self.assertIn(left[-1], batch.nodes)

    def test_dynamic_loops_reports_and_overflow(self):
        left = self.chain([2, 3], self.module.RowNext)
        right = self.chain([4, 5], self.module.ColumnNext)
        self.check_batch('LoopDot', [{'a': left[0], 'b': right[0]}])
        self.check_batch('ReportDot', [{'a': left[0], 'b': right[0]}])
        a, b = (self.module.Scalar(value=2 ** 62), self.module.Scalar(value=3))
        batch = self.multi.pack_cursors(self.schemas['Dot'], [self.module.Dot()], [{'a': a, 'b': b}])
        self.assertEqual(self.multi.run_jit(self.specs['Dot'], batch.buffers)[1], [3])
        with self.assertRaises(OverflowError):
            self.gpu.publish_results(self.schemas['Dot'], batch, batch.memory_plan(), '', 0)
        self.assertEqual(batch.walkers[0].total, 0)

    def test_cycle_round_limit_queue_full(self):
        a, b, c = [self.module.Scalar(value=1) for _ in range(3)]
        self.jac.connect(a, a, self.module.RowNext)
        self.jac.connect(b, b, self.module.ColumnNext)
        batch = self.multi.pack_cursors(self.schemas['Dot'], [self.module.Dot()], [dict(a=a, b=b)], 2, 5, prediction_budget=1)
        self.assertEqual(self.multi.run_jit(self.specs['Dot'], batch.buffers)[1], [2])
        self.jac.connect(a, c, self.module.RowNext)
        batch = self.multi.pack_cursors(self.schemas['Dot'], [self.module.Dot()], [dict(a=a, b=b)], 1, 5)
        self.assertEqual(self.multi.run_jit(self.specs['Dot'], batch.buffers)[1], [6])

    def test_batch_bfs_conflicts_budget_and_identity(self):
        rows = [[2], [3], [4], [5], [], []]
        order, meta = self.multi.predict_layout([[0, 1]], [rows], 6)
        self.assertEqual(order, [0, 1, 2, 3, 4, 5])
        order, meta = self.multi.predict_layout([[0, 1], [1, 0]], [rows, rows], 6, budget=1)
        self.assertEqual(sorted(order), list(range(6)))
        self.assertTrue(meta['channels'][0]['truncated'])
        self.assertEqual(order[:2], [0, 1])
        a, b = (self.module.Scalar(value=2), self.module.Scalar(value=2))
        batch = self.check_batch('Dot', [dict(a=a, b=a), dict(a=a, b=b)])
        self.assertEqual(len(batch.nodes), 2)

    def test_cursor_concatenation_complete_sequences_shared_and_fallback(self):
        a = [[3], [], [], [6], [], [], [], [], [], []]
        b = [[], [4, 6], [], [], [7], [], [], [], [], []]
        c = [[], [], [5], [], [], [8], [], [], [3], []]
        order, meta = self.multi.predict_layout([[0], [1], [2]], [a, b, c], 10)
        self.assertEqual(meta['strategy'], 'cursor_concatenation_first_occurrence')
        self.assertEqual(meta['candidate_orders'], [[0, 3, 6], [1, 4, 6, 7], [2, 5, 8, 3]])
        self.assertEqual(order, [0, 3, 6, 1, 4, 7, 2, 5, 8, 9])
        self.assertEqual(len(set(order)), 10)
        order, meta = self.multi.predict_layout([[0], [1], [2]], [a, b, c], 10, budget=1)
        self.assertEqual(order, [0, 3, 1, 4, 6, 2, 5, 7, 8, 9])
        self.assertTrue(all(s['truncated'] for s in meta['channels']))

    def test_whole_batch_bfs_precedes_next_cursor(self):
        a = [[4], [5], [], [], [], [], [], []]
        b = [[], [], [6], [7], [], [], [], []]
        order, meta = self.multi.predict_layout([[0, 1], [2, 3]], [a, b], 8)
        self.assertEqual(meta['candidate_orders'], [[0, 1, 4, 5], [2, 3, 6, 7]])
        self.assertEqual(order, [0, 1, 4, 5, 2, 3, 6, 7])

    def test_matmul_identity_order_complete_a_then_b(self):
        for m, k, n in ((4, 4, 4), (3, 5, 2)):
            walkers, starts, _ = self.module.build_matmul(
                [[i*k+q+1 for q in range(k)] for i in range(m)],
                [[q*n+j+1 for j in range(n)] for q in range(k)])
            current = self.multi.pack_cursors(self.schemas['Dot'], walkers, starts, 2, layout='current')
            predicted = self.multi.pack_cursors(self.schemas['Dot'], walkers, starts, 2)
            buffers = current.buffers
            size, lanes = len(current.nodes), m*n
            expected = []
            for ch, count in ((0, m), (1, n)):
                slots = [buffers.heads[ch*lanes+(i*n if ch == 0 else i)] for i in range(count)]
                for step in range(k):
                    expected.extend(id(current.nodes[slot]) for slot in slots)
                    if step < k-1:
                        slots = [buffers.targets[buffers.offsets[ch*(size+1)+slot]] for slot in slots]
            self.assertEqual([id(node) for node in predicted.nodes], expected)
            self.assertEqual(len(set(expected)), (m+n)*k)
            self.check_batch('Dot', starts, capacity=2)

    def test_random_integer_matmul_shared_inputs_and_output_fields(self):
        rng = random.Random(237)
        for m, n, k in [(2, 2, 3), (3, 4, 5), (1, 3, 2)]:
            a = [[rng.randrange(-5, 6) for _ in range(k)] for _ in range(m)]
            b = [[rng.randrange(-5, 6) for _ in range(n)] for _ in range(k)]
            walkers, starts, output = self.module.build_matmul(a, b)
            expected = [sum((a[i][q] * b[q][j] for q in range(k))) for i in range(m) for j in range(n)]
            batch = self.check_batch('Dot', starts)
            self.assertEqual([w.total for w in batch.walkers], expected)
            self.assertEqual(len(batch.nodes), (m + n) * k)
            self.assertEqual(len(set(map(id, batch.nodes))), (m + n) * k)
            for i, row in enumerate(output):
                for j, node in enumerate(row):
                    node.value = batch.walkers[i * n + j].total
            self.assertEqual([[node.value for node in row] for row in output], [expected[i * n:(i + 1) * n] for i in range(m)])
            self.assertTrue(all((set(nd.__dict__) - {'__jac__'} == {'value'} for nd in batch.nodes + [nd for row in output for nd in row])))

    def test_bindings_resources_and_chain_validation(self):
        nd = self.module.Scalar(value=1)
        for binding in ({'a': nd}, {'a': nd, 'b': 4}, {'a': nd, 'b': nd, 'c': nd}):
            with self.assertRaises((TypeError, ValueError)):
                self.multi.pack_cursors(self.schemas['Dot'], [self.module.Dot()], [binding])
        with self.assertRaises(ValueError):
            self.multi.pack_cursors(self.schemas['Dot'], [self.module.Dot()], [dict(a=nd, b=nd)], max_queue_bytes=1)
        with self.assertRaises(ValueError):
            self.multi.pack_cursors(self.schemas['Dot'], [self.module.Dot()], [dict(a=nd, b=nd)], max_nodes=0)
        schema = self.gpu.walker_schema(self.module.Dot, 'chain')
        batch = self.multi.pack_cursors(schema, [self.module.Dot()], [dict(a=nd, b=nd)])
        self.assertEqual(self.multi.run_jit(schema.cursor_spec, batch.buffers), ([[1]], [0]))
        if os.environ.get('JAC_GPU_TEST_CUDA') == '1':
            runtime = self.gpu.GpuWalkerRuntime(self.module.Dot, graph_format='chain')
            try:
                self.assertEqual(runtime.run_walkers([self.module.Dot()], [dict(a=nd, b=nd)]).values, [1])
            finally:
                runtime.close()
        self.jac.connect(nd, nd, self.module.RowNext)
        with self.assertRaises(ValueError):
            self.multi.pack_cursors(schema, [self.module.Dot()], [dict(a=nd, b=nd)])

    def test_seven_cursors_and_guard_statement_position(self):
        names = [f'c{i}' for i in range(7)]
        source = 'node Scalar { has value: int; } edge Next {} walker Seven { cursor ' + ','.join(names) + '; has total: int = 0; can step with (' + ','.join((n + ': Scalar entry' for n in reversed(names))) + ') { self.total += ' + '+'.join(('here[' + n + '].value' for n in names)) + '; ' + ' '.join(('visit[' + n + '] [->:Next:->];' for n in names)) + ' } }'
        path = Path(self.tmp.name) / 'seven.jac'
        path.write_text(source)
        mod = self.jac.jac_import(target=path.stem, base_path=str(path.parent))[0]
        schema = self.gpu.walker_schema(mod.Seven, 'csr')
        spec = schema.cursor_spec
        a, b = (mod.Scalar(value=2), mod.Scalar(value=3))
        self.jac.connect(a, b, mod.Next)
        binding = {n: a for n in names}
        expected = self.jac.spawn(binding, mod.Seven()).total
        batch = self.multi.pack_cursors(schema, [mod.Seven()], [binding])
        self.assertEqual(self.multi.run_jit(spec, batch.buffers), ([[expected]], [0]))
        self.assertEqual(expected, 35)
        if os.environ.get('JAC_GPU_TEST_CUDA') == '1':
            runtime = self.gpu.GpuWalkerRuntime(mod.Seven, graph_format='csr')
            try:
                self.assertEqual(runtime.run_walkers([mod.Seven()], [binding]).values, [35])
            finally:
                runtime.close()
        source = 'node Scalar { has value: int; } edge Next {}\nwalker GuardOrder { cursor a,b; has total: int = 0;\ncan step with (a: Scalar entry,b: Scalar entry) {\nif self.total == 0 { visit[a] [->:Next:->]; }\nself.total += here[a].value;\nvisit[b] [->:Next:->]; }}'
        path = Path(self.tmp.name) / 'guard_order.jac'
        path.write_text(source)
        mod = self.jac.jac_import(target=path.stem, base_path=str(path.parent))[0]
        schema = self.gpu.walker_schema(mod.GuardOrder, 'csr')
        a, b = (mod.Scalar(value=1), mod.Scalar(value=2))
        self.jac.connect(a, b, mod.Next)
        binding = dict(a=a, b=a)
        expected = self.jac.spawn(binding, mod.GuardOrder()).total
        batch = self.multi.pack_cursors(schema, [mod.GuardOrder()], [binding])
        self.assertEqual(expected, 3)
        self.assertEqual(self.multi.run_jit(schema.cursor_spec, batch.buffers), ([[expected]], [0]))

    def test_mock_cuda_marshalling_and_runtime_integration(self):
        import ctypes as c
        from test_runtime import DriverDouble
        from jaclang.runtime.gpu_cuda import CudaDriver, CudaSession
        from jaclang.compiler.backends.native.llvm import binding as llvm
        spec = self.specs['Three']
        schema = self.schemas['Three']
        nd = self.module.Scalar(value=7)
        batch = self.multi.pack_cursors(schema, [self.module.Three(), self.module.Three()], [dict(a=nd, b=nd, c=nd), dict(a=None, b=nd, c=nd)])
        arrays = batch.buffers.arrays()
        types = [c.c_uint32 if buf.typecode == 'I' else c.c_int64 for buf in arrays]
        target = llvm.Target.from_default_triple().create_target_machine(opt=2)
        engine = llvm.create_mcjit_compiler(self.multi.build_cursor_module([spec], target, False), target)
        engine.finalize_object()
        lane = c.CFUNCTYPE(None, *[c.POINTER(t) for t in types], *[c.c_uint64] * 6)(engine.get_function_address('jac_Three_cursors_lane'))

        class MultiDriver(DriverDouble):

            def launch(self, function, gx, gy, gz, bx, by, bz, shared, stream, params, extra):
                if self.fail_launch:
                    return 700
                args = [c.cast(params[i], c.POINTER(c.c_uint64))[0] for i in range(len(arrays) + 5)]
                self.assert_aligned = all((addr % 256 == 0 for addr in args[:len(arrays)]))
                ptrs = [c.cast(addr, c.POINTER(t)) for addr, t in zip(args, types)]
                for i in reversed(range(gx * bx)):
                    self.lane(*ptrs, *args[len(arrays):], i)
                self.launches.append((gx, bx))
                return 0
        driver = MultiDriver(lane, scalar=c.c_int64, kernel_name=schema.kernel_name)
        runtime = self.gpu.GpuWalkerRuntime(self.module.Three, graph_format='csr')
        runtime.session = CudaSession(schema.ptx, schema.kernel_name, driver=CudaDriver(driver), graph_format='csr', node_dtypes=schema.node_types(), state_dtypes=schema.state_types())
        try:
            result = runtime.run_walkers(batch.walkers, [dict(a=nd, b=nd, c=nd), dict(a=None, b=nd, c=nd)])
            self.assertEqual(result.values, [21, 0])
            self.assertTrue(driver.assert_aligned)
            self.assertGreater(result.memory.payload_bytes(), 0)
            self.assertGreaterEqual(result.memory.allocated_bytes(), result.memory.payload_bytes())
        finally:
            runtime.close()
        self.assertIsNone(driver.callback_error)
        self.assertFalse(driver.allocations)
        self.assertFalse(driver.contexts)
        self.assertFalse(driver.modules)

    def test_unsupported_subsets_explicit(self):
        original = (Path(__file__).resolve().parents[2] / 'jac/examples/gpu/named_cursors.jac').read_text().split('walker Three')[0]
        variants = [original.replace('b: Scalar entry', 'b: Other entry'), original.replace('visit[a] [->:RowNext:->];', 'while True { visit[a] [->:RowNext:->]; }'), original.replace('visit[a] [->:RowNext:->];', 'visit[a] [->:RowNext:->]; visit[a] [->:RowNext:->];'), original.replace('visit[a] [->:RowNext:->];', 'visit[a] [here[b] ->:RowNext:->];')]
        for i, source in enumerate(variants):
            path = Path(self.tmp.name) / f'bad{i}.jac'
            path.write_text(source)
            with self.subTest(i=i), self.assertRaises(self.unsupported):
                self.select(self.frontend(str(path)), ['Dot'])
if __name__ == '__main__':
    unittest.main()
