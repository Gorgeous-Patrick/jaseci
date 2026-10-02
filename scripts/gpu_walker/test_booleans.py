"""Boolean columns, short-circuit expressions, tagged reports and real CUDA."""

from array import array
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import struct
import unittest

import test_reports as report_support
from test_reports import ReportKernel, ReportDriver


class BooleanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        report_support.ReportTests.setUpClass.__func__(cls)
        cls.on_cuda = os.environ.get('JAC_GPU_TEST_CUDA') == '1'
        cls.counter = 0

    @classmethod
    def tearDownClass(cls):
        report_support.ReportTests.tearDownClass.__func__(cls)

    def variant(self, source=None, floating=False):
        source = source or (Path(__file__).resolve().parents[2] /
                            'jac/examples/gpu/booleans.jac').read_text()
        if floating:
            source = source.replace('value: int', 'value: float').replace('total: int = 0', 'total: float = 0.0')
            source = source.replace('here.value > 0', 'here.value > 0.0')
        path = self.folder / f'boolean_{type(self).counter}.jac'
        type(self).counter += 1
        path.write_text(source)
        spec = self.select(self.compile(str(path)), ['Collector'])[0]
        module = self.jac.jac_import(target=path.stem, base_path=str(path.parent))[0]
        return spec, module

    def runtime(self, spec, module, fmt, capacity=32, cuda=None):
        actual = self.on_cuda if cuda is None else cuda
        kernel = ReportKernel(spec, fmt)
        driver = None if actual else ReportDriver(kernel)
        runtime = self.gpu.GpuWalkerRuntime(module.Collector, graph_format=fmt,
            report_capacity=capacity, queue_capacity=32, max_visits=100)
        runtime.session = self.cuda.CudaSession(kernel.artifact.ptx, kernel.artifact.kernels[0]['name'],
            graph_format=fmt, node_field_count=len(spec.field_paths()), state_field_count=len(spec.state_paths()),
            emits_reports=bool(spec.report_parameters()), node_dtypes=spec.node_types(),
            state_dtypes=spec.state_types(), tagged_reports=runtime.schema.tagged_reports,
            driver=None if actual else self.cuda.CudaDriver(library=driver))
        self.addCleanup(runtime.close)
        return runtime, kernel

    def graph(self, module, rows, floating=False):
        cast = float if floating else int
        nodes = [module.Sample(flags=module.Flags(enabled=i != 1), value=cast([2, -1, 3][i]))
                 for i in range(len(rows))]
        for node, row in zip(nodes, rows):
            for target in row:
                self.jac.connect(node, nodes[target], module.Link)
        return nodes

    def assert_typed(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for a, b in zip(actual, expected):
            self.assertIs(type(a), type(b))
            if type(b) is float:
                self.assertEqual(struct.pack('=d', a), struct.pack('=d', b))
            else:
                self.assertEqual(a, b)

    def test_mixed_fields_nested_flags_and_reports_match_serial(self):
        for floating in (False, True):
            spec, module = self.variant(floating=floating)
            cast = float if floating else int
            for fmt, rows in [('chain', [[1], [2], []]), ('csr', [[1, 2], [2], []])]:
                runtime, kernel = self.runtime(spec, module, fmt)
                self.assertEqual(kernel.artifact.format, f'jac-ptx-{fmt}-v5')
                nodes = self.graph(module, rows, floating)
                for count in (0, 1, 31, 32, 33, 257, 1000):
                    with self.subTest(floating=floating, fmt=fmt, count=count):
                        starts = [None if i % 5 == 0 else nodes[i % 3] for i in range(count)]
                        walkers = [module.Collector(total=cast(i), accepted=i % 2 == 0) for i in range(count)]
                        expected = []
                        for i, start in enumerate(starts):
                            w = module.Collector(total=cast(i), accepted=i % 2 == 0)
                            if start is not None:
                                with redirect_stdout(io.StringIO()):
                                    self.jac.spawn(w, start)
                            expected.append(w)
                        result = runtime.run_walkers(walkers, starts)
                        for actual, reference in zip(walkers, expected):
                            self.assert_typed([actual.accepted, actual.total, actual.last],
                                              [reference.accepted, reference.total, reference.last])
                            self.assert_typed(actual.reports, reference.reports)
                        self.assertEqual(result.fields['accepted'], [w.accepted for w in expected])
                        self.assertTrue(all(type(v) is bool for v in result.fields['accepted']))
                        self.assertEqual(result.reports, [w.reports for w in expected])

    def test_boolean_only_fields_literals_and_assignments(self):
        source = '''node Sample { has enabled: bool; } edge Link {}
        walker Collector { has flag: bool = False;
            can step with Sample entry {
                self.flag = here.enabled and not self.flag;
                report self.flag;
                report True;
                report here.enabled == False;
                visit [->:Link:->];
            }
        }'''
        spec, module = self.variant(source)
        for fmt in ('chain', 'csr'):
            runtime, _ = self.runtime(spec, module, fmt)
            walkers = [module.Collector() for _ in range(33)]
            nodes = [module.Sample(enabled=i % 2 == 0) for i in range(33)]
            result = runtime.run_walkers(walkers, nodes)
            self.assertEqual(result.values, [i % 2 == 0 for i in range(33)])
            self.assertTrue(all(type(v) is bool for v in result.values))
            for i, w in enumerate(walkers):
                self.assert_typed(w.reports, [i % 2 == 0, True, i % 2 != 0])

    def test_short_circuit_skips_arithmetic_faults_and_preserves_failures(self):
        source = '''node Sample { has enabled: bool, value: int; } edge Link {}
        walker Collector { has flag: bool = False, total: int = 0;
            can step with Sample entry {
                self.flag = here.enabled and (1 % here.value == 0);
                report self.flag;
                self.flag = not here.enabled or (1 % here.value == 0);
                report self.flag;
                visit [->:Link:->];
            }
        }'''
        spec, module = self.variant(source)
        for fmt in ('chain', 'csr'):
            runtime, _ = self.runtime(spec, module, fmt)
            w = module.Collector()
            runtime.run_walkers([w], [module.Sample(enabled=False, value=0)])
            self.assert_typed(w.reports, [False, True])
            with self.assertRaises(ZeroDivisionError):
                runtime.run_walkers([w], [module.Sample(enabled=True, value=0)])
            self.assert_typed(w.reports, [False, True])
            self.assertIs(w.flag, True)

    def test_report_layout_tags_precision_and_capacity_rollback(self):
        spec, module = self.variant()
        runtime, _ = self.runtime(spec, module, 'csr', capacity=3)
        nodes = [module.Sample(flags=module.Flags(enabled=True), value=2**53 + 1) for _ in range(4)]
        walkers = [module.Collector(total=i) for i in range(4)]
        batch = runtime.prepare(walkers, nodes)
        plan = runtime.session.execute(batch.buffers)
        tags = batch.buffers.reports.tags
        self.assertEqual(list(tags), [1] * 4 + [2] * 4 + [1] * 4)
        result = self.gpu.publish_results(runtime.schema, batch, plan, '', 0)
        for i, reports in enumerate(result.reports):
            self.assert_typed(reports, [True, 2**53 + 1 + i, False])
        runtime.report_capacity = 2
        before = [(w.accepted, w.total, w.last, list(w.reports)) for w in walkers]
        with self.assertRaisesRegex(RuntimeError, 'report capacity'):
            runtime.run_walkers(walkers, nodes)
        self.assertEqual([(w.accepted, w.total, w.last, w.reports) for w in walkers], before)

    def test_boolean_fields_without_reports_and_numeric_reports_with_boolean_first(self):
        base = '''node Sample { has enabled: bool, value: float; } edge Link {}
        walker Collector { has flag: bool = False, total: float = 0.0;
            can step with Sample entry {
                self.flag = here.enabled;
                if self.flag { self.total += here.value; }
                REPORT
                visit [->:Link:->];
            }
        }'''
        for report in ('', 'report self.total;'):
            spec, module = self.variant(base.replace('REPORT', report))
            for fmt in ('chain', 'csr'):
                runtime, _ = self.runtime(spec, module, fmt)
                w = module.Collector()
                result = runtime.run_walkers([w], [module.Sample(enabled=True, value=-0.0)])
                self.assertIs(w.flag, True)
                self.assertEqual(w.reports, [0.0] if report else [])
                self.assertFalse(result.memory.tagged_reports)

    def test_boolean_validation_and_corrupt_tags_do_not_publish(self):
        spec, module = self.variant()
        runtime, _ = self.runtime(spec, module, 'chain', cuda=False)
        w = module.Collector()
        node = module.Sample(flags=module.Flags(enabled=True), value=2)
        for obj, field in ((w, 'accepted'), (node.flags, 'enabled')):
            setattr(obj, field, 1)
            with self.assertRaisesRegex(TypeError, 'bool'):
                runtime.prepare([w], [node])
            setattr(obj, field, False)
        batch = runtime.prepare([w], [node])
        batch.buffers.values[0] = 2
        with self.assertRaisesRegex(ValueError, 'canonical'):
            runtime.session.execute(batch.buffers)
        batch.buffers.values[0] = 1
        plan = runtime.session.execute(batch.buffers)
        batch.buffers.reports.tags[0] = 99
        with self.assertRaisesRegex(RuntimeError, 'report tag'):
            self.gpu.publish_results(runtime.schema, batch, plan, '', 0)
        self.assertIs(w.accepted, False)
        self.assertEqual(w.total, 0)
        self.assertEqual(w.reports, [])


if __name__ == '__main__':
    unittest.main()
