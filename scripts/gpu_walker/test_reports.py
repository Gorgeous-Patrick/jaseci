"""Numeric report ordering, bounded storage and publication; optional real CUDA."""

from array import array
import ctypes as c
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import tempfile
import unittest

from test_runtime import DriverDouble


class ReportKernel:
    def __init__(self, spec, graph_format):
        from jaclang.compiler.backends.native import ptx_walker, ptx_csr
        from jaclang.compiler.backends.native.llvm import binding as llvm
        csr = graph_format == 'csr'
        build = ptx_csr.build_csr_module if csr else ptx_walker.build_chain_module
        emit = ptx_csr.emit_csr_ptx if csr else ptx_walker.emit_chain_ptx
        target = llvm.Target.from_default_triple().create_target_machine(opt=2)
        module = build([spec], target, device=False)
        module.verify()
        self.engine = llvm.create_mcjit_compiler(module, target)
        self.engine.finalize_object()
        self.artifact = emit([spec])
        self.parameters = self.artifact.kernels[0]['parameters']
        types = {'int64': c.c_int64, 'float64': c.c_double,
                 'uint64': c.c_uint64, 'uint32': c.c_uint32}
        self.types = [c.POINTER(types[p['dtype']]) if 'length' in p else types[p['dtype']]
                      for p in self.parameters]
        self.scalar = types[spec.dtype.value]
        self.lane = c.CFUNCTYPE(None, *self.types, c.c_uint64)(
            self.engine.get_function_address(f'jac_{spec.name}_{"csr_" if csr else ""}lane'))


class ReportDriver(DriverDouble):
    def __init__(self, kernel):
        self.kernel = kernel
        super().__init__(kernel.lane, kernel.scalar, kernel.artifact.kernels[0]['name'])

    def launch(self, function, gx, gy, gz, bx, by, bz, shared, stream, params, extra):
        if self.fail_launch:
            return 700
        args = []
        for i, (p, typ) in enumerate(zip(self.kernel.parameters, self.kernel.types)):
            value = c.cast(params[i], c.POINTER(c.c_uint64))[0]
            if 'length' in p:
                assert value % 256 == 0
                args.append(c.cast(value, typ))
            else:
                args.append(value)
        for lane in reversed(range(gx * bx)):
            self.kernel.lane(*args, lane)
        self.launches.append((gx, bx))
        return 0


class ReportTests(unittest.TestCase):
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
        base, target = JacRuntime.get_base_path_dir(), JacRuntime.get_full_target_path()
        try:
            JacRuntime.set_base_path(None)
            JacRuntime.set_full_target_path(None)
            context = ExecutionContext()
        finally:
            JacRuntime.set_base_path(base)
            JacRuntime.set_full_target_path(target)
        cls.context = context
        cls.token = JacRuntime.push_request_context(context)
        cls.tmp = tempfile.TemporaryDirectory(prefix='jac_gpu_reports_')
        cls.folder = Path(cls.tmp.name)
        cls.variant_id = 0

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)
            cls.tmp.cleanup()

    def variant(self, body=None, floating=False):
        typ = 'float' if floating else 'int'
        zero = '0.0' if floating else '0'
        body = body or f'''report self.total;
            self.total += here.value;
            self.last = here.value;
            report self.total;
            if here.value > {zero} {{ report here.value * here.value; }}'''
        path = self.folder / f'report_variant_{type(self).variant_id}.jac'
        type(self).variant_id += 1
        path.write_text(f'''node Cell {{ has value: {typ}; }}
            edge Link {{}}
            walker Collector {{ has total: {typ} = {zero}, last: {typ} = {zero};
                can step with Cell entry {{ {body} visit [->:Link:->]; }} }}''')
        spec = self.select(self.compile(str(path)), ['Collector'])[0]
        module = self.jac.jac_import(target=path.stem, base_path=str(path.parent))[0]
        return spec, module

    def runtime(self, spec, module, graph_format, capacity=32, actual=False):
        kernel = ReportKernel(spec, graph_format)
        double = None if actual else ReportDriver(kernel)
        session = self.cuda.CudaSession(kernel.artifact.ptx, kernel.artifact.kernels[0]['name'],
            graph_format=graph_format, state_field_count=2, emits_reports=True,
            driver=None if actual else self.cuda.CudaDriver(library=double))
        runtime = self.gpu.GpuWalkerRuntime(module.Collector, graph_format=graph_format,
            queue_capacity=32, max_visits=100, report_capacity=capacity)
        runtime.session = session
        self.addCleanup(runtime.close)
        return runtime, kernel, double

    def graph(self, module, values, rows):
        nodes = [module.Cell(value=v) for v in values]
        for node, row in zip(nodes, rows):
            for target in row:
                self.jac.connect(node, nodes[target], module.Link)
        return nodes

    def test_reports_match_serial_order_and_repeated_csr_arrivals(self):
        for floating in (False, True):
            spec, module = self.variant(floating=floating)
            cast = float if floating else int
            for fmt, rows in [('chain', [[1], [2], []]), ('csr', [[1, 2], [2], []])]:
                with self.subTest(floating=floating, graph_format=fmt):
                    nodes = self.graph(module, list(map(cast, [2, -1, 3])), rows)
                    runtime, kernel, _ = self.runtime(spec, module, fmt)
                    heads = [nodes[0], nodes[1], nodes[2], None, nodes[0]]
                    walkers = [module.Collector(total=cast(i)) for i in range(len(heads))]
                    expected = []
                    for i, node in enumerate(heads):
                        w = module.Collector(total=cast(i))
                        if node is not None:
                            with redirect_stdout(io.StringIO()):
                                self.jac.spawn(w, node)
                        expected.append((w.total, w.last, list(w.reports)))
                    result = runtime.run_walkers(walkers, heads)
                    self.assertEqual([(w.total, w.last, w.reports) for w in walkers], expected)
                    self.assertEqual(result.reports, [v[2] for v in expected])
                    self.assertEqual(kernel.artifact.format, f'jac-ptx-{fmt}-v4')

    def test_report_slots_interleave_and_repeated_calls_replace_reports(self):
        spec, module = self.variant(body='report self.total; self.total += here.value; report self.total;')
        runtime, _, double = self.runtime(spec, module, 'chain', capacity=2)
        walkers = [module.Collector(total=i * 10) for i in range(4)]
        nodes = [module.Cell(value=1) for _ in walkers]
        batch = runtime.prepare(walkers, nodes)
        plan = runtime.session.execute(batch.buffers)
        self.assertEqual(list(batch.buffers.reports.counts), [2] * 4)
        self.assertEqual(list(batch.buffers.reports.values), [0, 10, 20, 30, 1, 11, 21, 31])
        self.assertEqual(plan.allocated_bytes(), sum(size for _, size in double.allocations.values()))
        self.gpu.publish_results(runtime.schema, batch, plan, '', 0)
        runtime.run_walkers(walkers, nodes)
        self.assertEqual([w.reports for w in walkers], [[1, 2], [11, 12], [21, 22], [31, 32]])
        # Empty traversal clears earlier reports and resets the device count.
        runtime.run_walkers(walkers, [None] * 4)
        self.assertEqual([w.reports for w in walkers], [[]] * 4)
        self.assertFalse(runtime.run_walkers([], []).gpu_executed)
        result = runtime.run_walkers(walkers[:1], nodes[:1])
        self.assertEqual(result.reports, [[2, 3]])
        self.assertEqual(result.memory.allocated_bytes(), sum(size for _, size in double.allocations.values()))

    def test_overflow_preserves_every_walkers_state_and_existing_reports(self):
        spec, module = self.variant(body='report here.value; self.total += here.value;')
        for fmt in ('chain', 'csr'):
            runtime, _, _ = self.runtime(spec, module, fmt, capacity=1)
            nodes = self.graph(module, [1, 2], [[1], []])
            walkers = [module.Collector(total=7), module.Collector(total=9)]
            for w in walkers:
                w.reports = [123]
            with self.assertRaisesRegex(RuntimeError, 'report capacity'):
                runtime.run_walkers(walkers, [nodes[1], nodes[0]])
            self.assertEqual([w.total for w in walkers], [7, 9])
            self.assertEqual([w.reports for w in walkers], [[123], [123]])
            runtime.report_capacity = 4
            result = runtime.run_walkers(walkers, [nodes[1], nodes[0]])
            self.assertEqual(result.reports, [[2], [1, 2]])
            self.assertEqual([w.total for w in walkers], [9, 12])

    def test_arithmetic_failure_after_report_does_not_publish(self):
        spec, module = self.variant(body='report here.value; self.total += here.value;')
        runtime, _, _ = self.runtime(spec, module, 'csr')
        walkers = [module.Collector(total=0), module.Collector(total=2**63 - 1)]
        for w in walkers:
            w.reports = [123]
        with self.assertRaises(OverflowError):
            runtime.run_walkers(walkers, [module.Cell(value=1)] * 2)
        self.assertEqual([w.total for w in walkers], [0, 2**63 - 1])
        self.assertEqual([w.reports for w in walkers], [[123], [123]])

    def test_integer_precision_and_invalid_counts_prevent_publication(self):
        spec, module = self.variant(body='report here.value; self.total += here.value;')
        runtime, _, _ = self.runtime(spec, module, 'csr')
        w = module.Collector()
        node = module.Cell(value=2**53 + 1)
        result = runtime.run_walkers([w], [node])
        self.assertEqual(result.reports, [[2**53 + 1]])
        w.reports = [55]
        batch = runtime.prepare([w], [node])
        plan = runtime.session.execute(batch.buffers)
        batch.buffers.reports.counts[0] = 33
        with self.assertRaisesRegex(RuntimeError, 'Invalid GPU report count'):
            self.gpu.publish_results(runtime.schema, batch, plan, '', 0)
        self.assertEqual(w.total, 2**53 + 1)
        self.assertEqual(w.reports, [55])

    def test_report_bounds_guarded_buffers_and_warp_boundary_batches(self):
        spec, _ = self.variant(body='report here.value; report self.total;')
        for fmt in ('chain', 'csr'):
            kernel = ReportKernel(spec, fmt)
            for m in (0, 1, 31, 32, 33, 257):
                for capacity in (1, 2):
                    with self.subTest(format=fmt, walkers=m, capacity=capacity):
                        make = self.memory.csr_buffers if fmt == 'csr' else self.memory.chain_buffers
                        topology = ([0, 0], []) if fmt == 'csr' else ([-1],)
                        buffers = make([5], *topology, [0] * m, [7] * m,
                                       self.memory.GpuScalarType.INT64, extra_initial=[[0] * m])
                        report_counts = (c.c_uint64 * (m + 2))(*([9191] * (m + 2)))
                        report_values = (c.c_int64 * (m * capacity + 2))(*([-713] * (m * capacity + 2)))
                        queue = (c.c_int64 * (m * 1024))()
                        args = [c.cast(a.buffer_info()[0], typ)
                                for a, typ in zip(buffers.arrays(), kernel.types)]
                        if fmt == 'csr':
                            args += [queue, 1, 0, m, 1024, 100]
                        else:
                            args += [1, m]
                        args += [c.cast(c.byref(report_counts, 8), c.POINTER(c.c_uint64)),
                                 c.cast(c.byref(report_values, 8), c.POINTER(c.c_int64)), capacity]
                        for lane in reversed(range(m)):
                            kernel.lane(*args, lane)
                        # Out-of-range lanes must touch no pointers.
                        null_args = [None if 'length' in p else 0 for p in kernel.parameters]
                        null_args[next(i for i, p in enumerate(kernel.parameters)
                                       if p['name'] == 'walker_count')] = m
                        for lane in (m, 2**32, 2**64 - 1):
                            kernel.lane(*null_args, lane)
                        self.assertEqual((report_counts[0], report_counts[-1]), (9191, 9191))
                        self.assertEqual((report_values[0], report_values[-1]), (-713, -713))
                        self.assertEqual(list(report_counts)[1:-1], [min(2, capacity)] * m)
                        self.assertEqual(list(report_values)[1:-1], [5] * m + ([7] * m if capacity == 2 else []))
                        self.assertEqual(list(buffers.status), [7 if capacity == 1 else 0] * m)

    def test_capacity_validation_and_unsupported_object_reports(self):
        for capacity in (0, -1, True, 1.5, 2**63):
            with self.subTest(capacity=capacity), self.assertRaises(ValueError):
                self.memory.check_report_capacity(capacity)
        for expr in ('here', 'self', '"hello"', '[here.value]'):
            with self.subTest(expr=expr), self.assertRaises(self.unsupported):
                self.variant(body=f'report {expr};')

    @unittest.skipUnless(os.environ.get('JAC_GPU_TEST_CUDA') == '1', 'requires real CUDA')
    def test_real_cuda(self):
        spec, module = self.variant()
        for fmt in ('chain', 'csr'):
            runtime, _, _ = self.runtime(spec, module, fmt, actual=True)
            nodes = self.graph(module, [2, -1, 3], [[1], [2], []])
            expected = module.Collector()
            self.jac.spawn(expected, nodes[0])
            w = module.Collector()
            result = runtime.run_walkers([w], [nodes[0]])
            self.assertEqual((w.total, w.reports), (expected.total, expected.reports))
            self.assertTrue(result.gpu_executed)


if __name__ == '__main__':
    unittest.main()
