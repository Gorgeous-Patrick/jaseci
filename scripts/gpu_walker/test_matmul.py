"""Jac matmul correctness, packing layout, validation, and optional CUDA."""

import copy
import math
import os
from pathlib import Path
import random
import unittest

import test_reports as support
from test_reports import ReportKernel, ReportDriver


class MatmulTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        support.ReportTests.setUpClass.__func__(cls)
        cls.source = Path(__file__).resolve().parents[2] / 'jac/examples/gpu/matmul.jac'
        cls.api = cls.jac.jac_import(target='matmul_api', base_path=str(cls.source.parent))[0]
        cls.spec = cls.select(cls.compile(str(cls.source)), ['DotProduct'])[0]

    @classmethod
    def tearDownClass(cls):
        support.ReportTests.tearDownClass.__func__(cls)

    def runtime(self):
        kernel = ReportKernel(self.spec, 'chain')
        runtime = self.gpu.GpuWalkerRuntime(self.api.DotProduct)
        runtime.session = self.cuda.CudaSession(
            kernel.artifact.ptx, kernel.artifact.kernels[0]['name'],
            node_field_count=2,
            driver=self.cuda.CudaDriver(library=ReportDriver(kernel)))
        self.addCleanup(runtime.close)
        # Retain the JIT engine for the driver's function pointer lifetime.
        runtime._matmul_kernel = kernel
        return runtime

    def cases(self):
        yield [[-2.0]], [[3.0]]
        yield [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]]
        yield [[1.0, 0.0], [0.0, 1.0]], [[-3.0, 2.0], [4.0, -5.0]]
        yield [[0.0] * 3 for _ in range(2)], [[float(i + j) for j in range(5)] for i in range(3)]
        rng = random.Random(7)
        for columns in (31, 32, 33):
            yield ([[rng.uniform(-2, 2) for _ in range(7)] for _ in range(3)],
                   [[rng.uniform(-2, 2) for _ in range(columns)] for _ in range(7)])

    def check_values(self, values, expected):
        self.assertEqual(len(values), len(expected))
        for actual_row, expected_row in zip(values, expected):
            self.assertEqual(len(actual_row), len(expected_row))
            for actual, reference in zip(actual_row, expected_row):
                self.assertTrue(math.isclose(actual, reference, rel_tol=1e-12, abs_tol=1e-12),
                                (actual, reference))

    def test_rectangular_products_and_input_preservation(self):
        runtime = self.runtime()
        for a, b in self.cases():
            before = copy.deepcopy((a, b))
            walkers, starts, rows, columns = self.api.matmul_graph(a, b)
            expected = self.api.serial_matmul(a, b)
            result = runtime.run_walkers(walkers, starts)
            actual = [result.values[i * columns:(i + 1) * columns] for i in range(rows)]
            self.check_values(actual, expected)
            self.assertEqual((a, b), before)
            self.assertEqual(result.status, [0] * (rows * columns))

    def test_k_major_columns_place_adjacent_walkers_next_to_each_other(self):
        a = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
        b = [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]]
        walkers, starts, rows, columns = self.api.matmul_graph(a, b)
        batch = self.runtime().prepare(walkers, starts)
        lanes = rows * columns
        self.assertEqual(list(batch.buffers.heads), list(range(lanes)))
        self.assertEqual(list(batch.buffers.links), list(range(lanes, 3 * lanes)) + [-1] * lanes)
        left, right = batch.buffers.columns()
        self.assertEqual(list(left), [a[row][k] for k in range(3) for row in range(rows) for col in range(columns)])
        self.assertEqual(list(right), [b[k][col] for k in range(3) for row in range(rows) for col in range(columns)])
        self.assertEqual(batch.memory_plan().payload_bytes(), 24 * rows * columns * 3 + 28 * lanes)

    def test_invalid_shapes_are_rejected(self):
        for a, b in (([], [[1.0]]), ([[]], [[1.0]]), ([[1.0]], []),
                     ([[1.0], [2.0, 3.0]], [[1.0]]),
                     ([[1.0]], [[1.0], [2.0]]),
                     ([[1.0, 2.0]], [[1.0], []])):
            for function in (self.api.matmul_graph, self.api.gpu_matmul, self.api.serial_matmul):
                with self.subTest(a=a, b=b, function=function.__name__):
                    with self.assertRaises(ValueError):
                        function(a, b)

    @unittest.skipUnless(os.environ.get('JAC_GPU_TEST_CUDA') == '1', 'opt-in real CUDA')
    def test_real_cuda(self):
        for a, b in self.cases():
            result = self.api.gpu_matmul(a, b)
            self.assertTrue(result.execution.gpu_executed)
            self.assertIn('NVIDIA', result.execution.gpu_name)
            self.check_values(result.values, self.api.serial_matmul(a, b))


if __name__ == '__main__':
    unittest.main()
