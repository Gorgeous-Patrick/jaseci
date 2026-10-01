"""Integer walker differential and host ABI tests; set JAC_GPU_TEST_CUDA=1 for CUDA."""

from array import array
import ctypes as c
import os
from pathlib import Path
import random
import tempfile
import unittest

from test_runtime import DriverDouble
from verify import CpuKernel, reorder_nodes

MIN, MAX = -(2**63), 2**63 - 1


class IntegerWalkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from jaclang.runtime.runtime import JacRuntime
        from jaclang.runtime.context import ExecutionContext
        from jaclang.runtime import gpu, gpu_cuda, gpu_memory
        from jaclang.compiler.backends.native.ptx import compile_ptx_frontend, PtxUnsupported
        from jaclang.compiler.backends.native.ptx_walker import select_chain_walkers, emit_chain_ptx
        from jaclang.compiler.backends.native.llvm import binding as llvm

        llvm.initialize_all_targets()
        llvm.initialize_all_asmprinters()
        cls.jac, cls.gpu, cls.cuda, cls.memory = JacRuntime, gpu, gpu_cuda, gpu_memory
        cls.frontend, cls.select, cls.emit = staticmethod(compile_ptx_frontend), staticmethod(select_chain_walkers), staticmethod(emit_chain_ptx)
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
        cls.tmp = tempfile.TemporaryDirectory(prefix='jac-gpu-int-')
        source = Path(__file__).resolve().parents[2] / 'jac/examples/gpu/even_chain.jac'
        cls.example = JacRuntime.jac_import(target='even_chain', base_path=str(source.parent))[0]
        cls.spec = cls.select(cls.frontend(str(source)), ['EvenSum'])[0]

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)
            cls.tmp.cleanup()

    def variant(self, body):
        folder = Path(self.tmp.name)
        name = f'int_variant_{len(list(folder.glob("*.jac")))}'
        source = ('node IntCell { has value: int; }\nedge IntNext {}\n'
                  'walker EvenSum { has total: int = 0;\ncan step with IntCell entry {\n'
                  + body + '\nvisit [->:IntNext:->];\n}}\n')
        path = folder / f'{name}.jac'
        path.write_text(source)
        spec = self.select(self.frontend(str(path)), ['EvenSum'])[0]
        module = self.jac.jac_import(target=name, base_path=str(folder))[0]
        return spec, module

    def runner(self, spec):
        artifact = self.emit([spec])
        self.assertEqual(artifact.kernels[0]['scalar_dtype'], 'int64')
        self.assertEqual([p['dtype'] for p in artifact.kernels[0]['parameters'][:6]],
                         ['int64'] * 5 + ['uint32'])
        cpu = CpuKernel(spec)
        if not self.on_cuda:
            return cpu.run
        session = self.cuda.CudaSession(artifact.ptx, artifact.kernels[0]['name'])
        self.addCleanup(session.close)

        def run(values, links, heads, initial):
            expected, codes = cpu.run(values, links, heads, initial)
            buffers = self.memory.chain_buffers(values, links, heads, initial,
                                                 self.memory.GpuScalarType.INT64)
            buffers.results[:] = array('q', [cpu.sentinel]) * len(heads)
            session.execute(buffers)
            self.assertEqual(buffers.results.tolist(), expected)
            self.assertEqual(buffers.status.tolist(), codes)
            return expected, codes

        return run

    def reference(self, module, values, links, heads, initial):
        nodes = [module.IntCell(value=value) for value in values]
        for i, link in enumerate(links):
            if link != -1:
                self.jac.connect(nodes[i], nodes[link], module.IntNext)
        result = []
        for head, seed in zip(heads, initial):
            walker = module.EvenSum(total=seed)
            if head != -1:
                self.jac.spawn(walker, nodes[head])
            result.append(walker.total)
        return result

    def test_even_sum_exact_large_integers_shared_suffix_and_random_layout(self):
        run = self.runner(self.spec)
        values = [-7, -6, 0, 9, 12, 2**53 + 1, 2**53 + 2, MIN, MAX]
        links = [1, 2, 3, 4, -1, 6, -1, -1, -1]
        heads, initial = [0, 1, 5, 7, 8, -1], [3, -9, 3, 0, MAX, MIN]
        expected = self.reference(self.example, values, links, heads, initial)
        self.assertEqual(expected, [9, -3, 2**53 + 5, MIN, MAX, MIN])
        for seed in (928, 929, 930):
            order = list(range(len(values)))
            random.Random(seed).shuffle(order)
            actual, status = run(*reorder_nodes(values, links, heads, order), initial)
            self.assertEqual(actual, expected)
            self.assertEqual(status, [0] * len(heads))
        self.assertEqual(run([], [], [], []), ([], []))
        for count in (1, 31, 32, 33, 257, 1000):
            actual, status = run([2, 3, 4], [1, 2, -1], [0] * count, list(range(count)))
            self.assertEqual(actual, [i + 6 for i in range(count)])
            self.assertEqual(status, [0] * count)

    def test_integer_arithmetic_and_python_signed_modulo(self):
        pairs = [(x, y) for x in (MIN, MAX, -7, -2, 0, 2, 7, 2**53 + 1)
                 for y in (MIN, MAX, -3, -1, 1, 2, 3)]
        spec, module = self.variant('self.total = here.value % self.total;')
        run = self.runner(spec)
        values, initial = [p[0] for p in pairs], [p[1] for p in pairs]
        heads, links = list(range(len(pairs))), [-1] * len(pairs)
        expected = [x % y for x, y in pairs]
        self.assertEqual(self.reference(module, values, links, heads, initial), expected)
        self.assertEqual(run(values, links, heads, initial), (expected, [0] * len(pairs)))
        for body, expected in (
                ('self.total += here.value;', [8, -8]),
                ('self.total -= here.value;', [2, -2]),
                ('self.total *= here.value;', [15, 15]),
                ('self.total = -here.value;', [-3, 3]),
                ('self.total = +here.value;', [3, -3]),
                ('self.total %= here.value;', [2, -2])):
            spec, module = self.variant(body)
            inputs = ([3, -3], [-1, -1], [0, 1], [5, -5])
            self.assertEqual(self.reference(module, *inputs), expected)
            self.assertEqual(self.runner(spec)(*inputs), (expected, [0, 0]))

    def test_conditional_updates_are_lazy_and_preserve_traversal(self):
        spec, module = self.variant('''
            if here.value == 0 { self.total += 1; }
            elif here.value < 0 { self.total = self.total % here.value; }
            else { if here.value >= 2 { self.total *= 2; }
                   else { self.total -= 1; } }
        ''')
        inputs = ([0, -3, 1, 2], [1, 2, 3, -1], [0, 1, 2, 3], [5, 5, 5, 5])
        expected = self.reference(module, *inputs)
        self.assertEqual(self.runner(spec)(*inputs), (expected, [0] * 4))
        for comparison in ('!=', '<=', '>'):
            spec, module = self.variant(f'if here.value {comparison} 0 {{ self.total += here.value; }}')
            inputs = ([-2, 0, 2], [-1] * 3, [0, 1, 2], [5] * 3)
            self.assertEqual(self.runner(spec)(*inputs), (self.reference(module, *inputs), [0] * 3))
        spec, _ = self.variant('if here.value == 0 { self.total += 1; }')
        self.assertEqual(self.runner(spec)([1], [-1], [0], [MAX]), ([MAX], [0]))
        spec, _ = self.variant('if here.value != 0 { self.total = self.total % here.value; }')
        self.assertEqual(self.runner(spec)([0, 2], [-1, -1], [0, 1], [MAX, MAX]), ([MAX, 1], [0, 0]))
        spec, _ = self.variant('self.total = -9223372036854775808;')
        self.assertEqual(self.runner(spec)([0], [-1], [0], [0]), ([MIN], [0]))

    def test_arithmetic_faults_leave_result_slots_untouched(self):
        for body, values, seeds, codes in (
                ('self.total += here.value;', [1, -1, 1], [MAX, MIN, 0], [3, 3, 0]),
                ('self.total -= here.value;', [-1, 1, 1], [MAX, MIN, 1], [3, 3, 0]),
                ('self.total *= here.value;', [2, -1, 0], [MAX, MIN, MIN], [3, 3, 0]),
                ('self.total = -here.value;', [MIN, -1], [0, 0], [3, 0]),
                ('self.total = here.value % self.total;', [MIN, 7, MIN], [-1, 0, 1], [0, 4, 0])):
            spec, _ = self.variant(body)
            actual, status = self.runner(spec)(values, [-1] * len(values), list(range(len(values))), seeds)
            self.assertEqual(status, codes)
            for value, code in zip(actual, codes):
                if code:
                    self.assertEqual(value, -987654)
        # An intermediate overflow is an error even if a later operation would cancel it.
        spec, _ = self.variant('self.total = (self.total + here.value) - here.value;')
        self.assertEqual(self.runner(spec)([1], [-1], [0], [MAX])[1], [3])

    def test_runtime_integer_packing_publication_and_batch_rollback(self):
        runtime = self.gpu.GpuWalkerRuntime(self.example.EvenSum)
        self.addCleanup(runtime.close)
        if not self.on_cuda:
            cpu = CpuKernel(self.spec)
            double = DriverDouble(cpu.lane, c.c_int64, 'jac_EvenSum_batch')
            runtime.session = self.cuda.CudaSession(runtime.schema.ptx, runtime.schema.kernel_name,
                                                    driver=self.cuda.CudaDriver(library=double))
        walkers = [self.example.EvenSum(total=3), self.example.EvenSum(total=5)]
        nodes = [self.example.IntCell(value=2**53 + 2), self.example.IntCell(value=-2)]
        batch = runtime.prepare(walkers, nodes)
        self.assertEqual([a.typecode for a in batch.buffers.arrays()], ['q'] * 5 + ['I'])
        result = runtime.run_walkers(walkers, nodes)
        self.assertEqual(result.values, [2**53 + 5, 3])
        self.assertTrue(all(type(w.total) is int for w in walkers))
        walkers = [self.example.EvenSum(total=0), self.example.EvenSum(total=MAX)]
        nodes = [self.example.IntCell(value=2)] * 2
        with self.assertRaises(OverflowError):
            runtime.run_walkers(walkers, nodes)
        self.assertEqual([w.total for w in walkers], [0, MAX])
        spec, module = self.variant('self.total = here.value % self.total;')
        modulo_runtime = self.gpu.GpuWalkerRuntime(module.EvenSum)
        self.addCleanup(modulo_runtime.close)
        if not self.on_cuda:
            modulo_cpu = CpuKernel(spec)
            double = DriverDouble(modulo_cpu.lane, c.c_int64, 'jac_EvenSum_batch')
            modulo_runtime.session = self.cuda.CudaSession(
                modulo_runtime.schema.ptx, modulo_runtime.schema.kernel_name,
                driver=self.cuda.CudaDriver(library=double))
        modulo_walkers = [module.EvenSum(total=2), module.EvenSum(total=0)]
        with self.assertRaises(ZeroDivisionError):
            modulo_runtime.run_walkers(modulo_walkers, [module.IntCell(value=7)] * 2)
        self.assertEqual([w.total for w in modulo_walkers], [2, 0])
        for invalid, exception in ((True, TypeError), (2.0, TypeError), (MAX + 1, OverflowError), (MIN - 1, OverflowError)):
            for state in (False, True):
                walker, node = self.example.EvenSum(), self.example.IntCell(value=2)
                setattr(walker if state else node, 'total' if state else 'value', invalid)
                with self.assertRaises(exception):
                    runtime.prepare([walker], [node])

    def test_unsupported_updates_remain_compile_errors(self):
        # Sequential updates are now supported, including on a single state column.
        spec, _ = self.variant('if here.value == 0 { self.total += 1; self.total *= 2; }')
        self.assertEqual(self.runner(spec)([0, 1], [-1, -1], [0, 1], [3, 3]),
                         ([8, 3], [0, 0]))
        for body in (
                'self.total = here.value / 2;',
                'self.total = here.value + 2.0;',
                'self.total = here.value + 9223372036854775808;',
                'if here.value == 0 { here.value = 2; }',
                'if here.value == 0 { report here.value; }',
                'if here.value == 0 { visit [->:IntNext:->]; }',
                'if here.value == 0 { self.total += 1; } else { here.value = 2; }'):
            with self.subTest(body=body), self.assertRaises(self.unsupported):
                self.variant(body)


if __name__ == '__main__':
    unittest.main()
