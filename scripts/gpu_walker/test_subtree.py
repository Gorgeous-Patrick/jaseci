"""Batched subtree queries: serial equivalence, private state and optional CUDA."""

import os
from pathlib import Path
import random
import unittest

import test_reports as support
from test_reports import ReportKernel, ReportDriver


class SubtreeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        support.ReportTests.setUpClass.__func__(cls)
        cls.source = Path(__file__).resolve().parents[2] / 'jac/examples/gpu/subtree_query.jac'
        cls.model = cls.jac.jac_import(target='subtree_query', base_path=str(cls.source.parent))[0]
        cls.data = cls.jac.jac_import(target='subtree_query_data', base_path=str(cls.source.parent))[0]
        cls.spec = cls.select(cls.compile(str(cls.source)), ['SubtreeQuery'])[0]
        cls.actual = os.environ.get('JAC_GPU_TEST_CUDA') == '1'

    @classmethod
    def tearDownClass(cls):
        support.ReportTests.tearDownClass.__func__(cls)

    def runtime(self, nodes, queue_capacity=None):
        runtime = self.gpu.GpuWalkerRuntime(self.model.SubtreeQuery, graph_format='csr',
            queue_capacity=nodes if queue_capacity is None else queue_capacity, max_visits=nodes)
        if not self.actual:
            kernel = ReportKernel(self.spec, 'csr')
            runtime.session = self.cuda.CudaSession(
                kernel.artifact.ptx, kernel.artifact.kernels[0]['name'], graph_format='csr',
                node_field_count=len(self.spec.node_types()), state_field_count=len(self.spec.state_types()),
                node_dtypes=self.spec.node_types(), state_dtypes=self.spec.state_types(),
                driver=self.cuda.CudaDriver(library=ReportDriver(kernel)))
        self.addCleanup(runtime.close)
        return runtime

    def oracle(self, amounts, alerts, root, threshold):
        pending = [] if root is None else [root]
        visited = []
        while pending:
            current = pending.pop()
            visited.append(current)
            pending.extend(child for child in (current * 2 + 1, current * 2 + 2) if child < len(amounts))
        matches = [i for i in visited if amounts[i] >= threshold]
        return (len(matches), sum(amounts[i] for i in matches),
                any(alerts[i] for i in matches), len(visited), threshold)

    def output(self, w):
        return (w.count, w.total, w.has_alert, w.visited, w.threshold)

    def test_known_tree_and_query_specific_flags(self):
        amounts = [100, 50, 200, 20, 150, 80, 250]
        alerts = [False, True, False, False, True, False, True]
        nodes = self.data.make_tree(amounts, alerts)
        walkers = [self.model.SubtreeQuery(threshold=100) for _ in range(4)]
        result = self.runtime(7).run_walkers(walkers, nodes[:4])
        self.assertEqual(result.fields['count'], [4, 1, 2, 0])
        self.assertEqual(result.fields['total'], [700, 150, 450, 0])
        self.assertEqual(result.fields['has_alert'], [True, True, True, False])
        self.assertTrue(all(type(v) is bool for v in result.fields['has_alert']))
        self.assertEqual(result.memory.node_count, 7)
        self.assertEqual(result.memory.edge_count, 6)
        self.assertEqual(result.status, [0] * 4)
        if self.actual:
            self.assertTrue(result.gpu_executed)
            self.assertIn('NVIDIA', result.gpu_name)
        # An alert on an unqualified node must not count toward the query.
        unqualified = self.model.SubtreeQuery(threshold=100)
        self.runtime(1).run_walkers([unqualified], [self.model.Item(amount=50, alert=True)])
        self.assertEqual(self.output(unqualified), (0, 0, False, 1, 100))

    def test_shared_tree_matches_serial_and_independent_oracle(self):
        rng = random.Random(19)
        amounts = [rng.randrange(-100, 1000) for _ in range(127)]
        alerts = [rng.random() < 0.2 for _ in amounts]
        nodes = self.data.make_tree(amounts, alerts)
        runtime = self.runtime(len(nodes))
        for count in (0, 1, 31, 32, 33, 257, 1024):
            with self.subTest(count=count):
                roots = [None if i % 11 == 0 else i % len(nodes) for i in range(count)]
                thresholds = [(i * 37) % 1101 - 100 for i in range(count)]
                starts = [None if root is None else nodes[root] for root in roots]
                walkers = [self.model.SubtreeQuery(threshold=t) for t in thresholds]
                result = runtime.run_walkers(walkers, starts)
                for w, root, threshold, start in zip(walkers, roots, thresholds, starts):
                    expected = self.oracle(amounts, alerts, root, threshold)
                    self.assertEqual(self.output(w), expected)
                    reference = self.model.SubtreeQuery(threshold=threshold)
                    if start is not None:
                        self.jac.spawn(reference, start)
                    self.assertEqual(self.output(w), self.output(reference))
                self.assertEqual(result.fields['total'], [w.total for w in walkers])
                self.assertEqual(result.fields['has_alert'], [w.has_alert for w in walkers])
                self.assertEqual([(n.amount, n.alert) for n in nodes], list(zip(amounts, alerts)))

    def test_leaf_equality_and_exact_integer_precision(self):
        large = 2**53 + 1
        nodes = self.data.make_tree([large, -4, 3], [False, True, False])
        walkers = [self.model.SubtreeQuery(threshold=t) for t in (large, large + 1, -4)]
        self.runtime(3).run_walkers(walkers, [nodes[0], nodes[0], nodes[1]])
        self.assertEqual(self.output(walkers[0]), (1, large, False, 3, large))
        self.assertEqual(self.output(walkers[1]), (0, 0, False, 3, large + 1))
        self.assertEqual(self.output(walkers[2]), (1, -4, True, 1, -4))

    def test_invalid_demo_data_and_queue_failure_preserve_state(self):
        for amounts, alerts in (([], []), ([1], [])):
            with self.assertRaises(ValueError):
                self.data.make_tree(amounts, alerts)
        nodes = self.data.make_tree([1] * 7, [True] * 7)
        walkers = [self.model.SubtreeQuery(count=4, total=9, threshold=1),
                   self.model.SubtreeQuery(count=8, total=20, has_alert=True, threshold=2)]
        before = [self.output(w) for w in walkers]
        with self.assertRaisesRegex(RuntimeError, 'queue capacity'):
            self.runtime(7, queue_capacity=1).run_walkers(walkers, [nodes[0], nodes[3]])
        self.assertEqual([self.output(w) for w in walkers], before)


if __name__ == '__main__':
    unittest.main()
