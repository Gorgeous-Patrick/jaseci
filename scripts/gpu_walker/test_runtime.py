"""CPU-only tests of Jac object packing and the CUDA host ABI/lifecycle.

The driver double invokes CPU LLVM lowering. It neither loads nor executes PTX.
"""

import ctypes as c
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class DriverDouble(SimpleNamespace):
    """C-callable launch/copy/allocate hooks exercise actual ctypes marshalling."""

    def __init__(self, lane):
        super().__init__()
        self.lane = lane
        self.allocations = {}
        self.allocated_sizes = []
        self.stack = [0x1234]
        self.contexts = set()
        self.modules = set()
        self.launches = []
        self.fail_launch = False
        self.fail_sync = False
        self.fail_alloc = False
        self.free_bytes = 2**30
        self.corrupt_status = False
        self.on_sync = None
        self.error_name = c.create_string_buffer(b'TEST_DRIVER_ERROR')
        self.error_text = c.create_string_buffer(b'injected host test failure')
        self.callback_error = None
        p, u, i, ptr, size = c.c_void_p, c.c_uint, c.c_int, c.c_uint64, c.c_size_t
        callbacks = {
            'cuMemAlloc_v2': ([c.POINTER(ptr), size], self.allocate),
            'cuMemFree_v2': ([ptr], self.free),
            'cuMemcpyHtoD_v2': ([ptr, p, size], self.copy),
            'cuMemcpyDtoH_v2': ([p, ptr, size], self.copy),
            'cuLaunchKernel': ([p, u, u, u, u, u, u, u, p, c.POINTER(p), c.POINTER(p)], self.launch),
        }
        for name, (args, callback) in callbacks.items():
            setattr(self, name, c.CFUNCTYPE(i, *args)(self.guard(callback)))
        stubs = {
            'cuInit': lambda flags: 0,
            'cuDeviceGetCount': lambda out: self.store(out, i, 1),
            'cuDeviceGet': lambda out, ordinal: self.store(out, i, ordinal),
            'cuDeviceGetName': lambda out, length, dev: self.name(out),
            'cuDeviceGetAttribute': lambda out, attr, dev: self.store(out, i, {1: 1024, 2: 1024, 5: 2**31 - 1, 75: 8, 76: 6}[attr]),
            'cuDriverGetVersion': lambda out: self.store(out, i, 0),
            'cuGetErrorName': lambda code, out: self.store(out, p, c.addressof(self.error_name)),
            'cuGetErrorString': lambda code, out: self.store(out, p, c.addressof(self.error_text)),
            'cuCtxCreate_v2': self.create_context,
            'cuCtxDestroy_v2': self.destroy_context,
            'cuCtxPushCurrent_v2': self.push,
            'cuCtxPopCurrent_v2': self.pop,
            'cuCtxSynchronize': self.sync,
            'cuModuleLoadDataEx': self.load,
            'cuModuleGetFunction': lambda out, module, name: self.store(out, p, 0x4567),
            'cuModuleUnload': self.unload,
            'cuFuncGetAttribute': lambda out, attr, fn: self.store(out, i, 1024),
            'cuMemGetInfo_v2': lambda free, total: self.store(free, size, self.free_bytes) or self.store(total, size, 2**30),
        }
        for name, fn in stubs.items():
            # Function attributes (argtypes/restype) must be assignable.
            def bound(*args, fn=fn):
                return fn(*args)
            setattr(self, name, bound)

    @staticmethod
    def store(out, typ, value):
        c.cast(out, c.POINTER(typ))[0] = value
        return 0

    @staticmethod
    def value(handle):
        return handle.value if hasattr(handle, 'value') else handle

    def guard(self, callback):
        def guarded(*args):
            try:
                return callback(*args)
            except BaseException as error:
                self.callback_error = error
                return 999
        return guarded

    def name(self, out):
        c.memmove(out, b'CPU driver double\0', 18)
        return 0

    def create_context(self, out, flags, dev):
        self.contexts.add(0x2345)
        self.stack.append(0x2345)
        return self.store(out, c.c_void_p, 0x2345)

    def destroy_context(self, ctx):
        key = self.value(ctx)
        if self.stack[-1] == key:
            self.stack.pop()
        self.contexts.remove(key)
        self.modules.clear()
        return 0

    def push(self, ctx):
        self.stack.append(self.value(ctx))
        return 0

    def pop(self, out):
        return self.store(out, c.c_void_p, self.stack.pop())

    def load(self, out, image, count, options, values):
        assert b'.entry jac_ChainSum_batch(' in c.string_at(image)
        assert list(options) == [5, 6, 8] and values[1] == 8192
        self.modules.add(0x3456)
        return self.store(out, c.c_void_p, 0x3456)

    def unload(self, module):
        self.modules.remove(self.value(module))
        return 0

    def allocate(self, out, size):
        if self.fail_alloc:
            return 2
        # Emulate CUDA's aligned allocations, while using real 64-bit host pointers.
        buf = c.create_string_buffer(size + 255)
        address = (c.addressof(buf) + 255) & ~255
        self.allocations[address] = (buf, size)
        self.allocated_sizes.append(size)
        return self.store(out, c.c_uint64, address)

    def free(self, address):
        del self.allocations[address]
        return 0

    def copy(self, dst, src, size):
        c.memmove(dst, src, size)
        return 0

    def launch(self, function, gx, gy, gz, bx, by, bz, shared, stream, params, extra):
        if self.fail_launch:
            return 700
        args = [c.cast(params[i], c.POINTER(c.c_uint64))[0] for i in range(8)]
        assert (gy, gz, by, bz, shared, stream, bool(extra)) == (1, 1, 1, 1, 0, None, False)
        assert all(address % 256 == 0 for address in args[:6] if address)
        ptrs = [c.cast(address, c.POINTER(typ)) for address, typ in zip(args, (
            c.c_double, c.c_int64, c.c_int64, c.c_double, c.c_double, c.c_uint32,
        ))]
        n, m = args[6:]
        for index in reversed(range(gx * bx)):
            self.lane(*ptrs, n, m, index)
        if self.corrupt_status:
            ptrs[5][0] = 1
        self.launches.append((gx, bx, n, m))
        return 0

    def sync(self):
        if self.on_sync:
            self.on_sync()
        return 700 if self.fail_sync else 0


class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from jaclang.runtime.runtime import JacRuntime
        from jaclang.runtime.context import ExecutionContext
        from jaclang.runtime import gpu, gpu_cuda, gpu_memory
        from jaclang.compiler.backends.native.ptx import compile_ptx_frontend
        from jaclang.compiler.backends.native.ptx_walker import select_chain_walkers
        from verify import CpuKernel
        cls.jac, cls.gpu, cls.cuda, cls.memory = JacRuntime, gpu, gpu_cuda, gpu_memory
        base, target = JacRuntime.get_base_path_dir(), JacRuntime.get_full_target_path()
        try:
            JacRuntime.set_base_path(None)
            JacRuntime.set_full_target_path(None)
            cls.context = ExecutionContext()
        finally:
            JacRuntime.set_base_path(base)
            JacRuntime.set_full_target_path(target)
        cls.token = JacRuntime.push_request_context(cls.context)
        source = Path(__file__).resolve().parents[2] / 'jac/examples/gpu/chain.jac'
        cls.chain = JacRuntime.jac_import(target='chain', base_path=str(source.parent))[0]
        cls.schema = gpu.walker_schema(cls.chain.ChainSum)
        spec = select_chain_walkers(compile_ptx_frontend(str(source)), ['ChainSum'])[0]
        cls.cpu = CpuKernel(spec)

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)

    def nodes(self):
        nodes = [self.chain.Cell(value=float(i + 1)) for i in range(12)]
        for base in (0, 3, 6, 9):
            for index in (base, base + 1):
                self.jac.connect(nodes[index], nodes[index + 1], self.chain.Next)
        return nodes

    def driver(self):
        double = DriverDouble(self.cpu.lane)
        driver = self.cuda.CudaDriver(library=double)
        session = self.cuda.CudaSession(self.schema.ptx, self.schema.kernel_name, driver=driver)
        self.addCleanup(session.close)
        self.assertEqual(double.stack, [0x1234])
        return double, session

    def test_layout_matches_walkers_and_deduplicates_shared_suffix(self):
        nodes = self.nodes()
        walkers = [self.chain.ChainSum(total=float(10 * i)) for i in range(5)]
        batch = self.gpu.pack_walkers(self.schema, walkers, [nodes[i] for i in (0, 3, 6, 9, 1)])
        self.assertEqual(len(batch.nodes), 12)
        self.assertEqual(batch.buffers.heads.tolist(), [0, 1, 2, 3, 4])
        self.assertIs(batch.nodes[4], nodes[1])
        self.assertEqual(batch.buffers.links[0], 4)
        self.assertEqual([w.total for w in walkers], [0, 10, 20, 30, 40])
        self.assertTrue(nodes[0].__jac__.out_light)
        self.assertEqual(nodes[0].__jac__.edges, [])

    def test_driver_abi_copyback_and_reuse_refresh(self):
        nodes = self.nodes()
        walkers = [self.chain.ChainSum(total=float(10 * i)) for i in range(4)]
        starts = [nodes[i] for i in (0, 3, 6, 9)]
        double, session = self.driver()
        batch = self.gpu.pack_walkers(self.schema, walkers, starts)
        plan = session.execute(batch.buffers)
        result = self.gpu.publish_results(self.schema, batch, plan, session.gpu_name, 0)
        self.assertEqual(result.values, [6, 25, 44, 63])
        self.assertEqual([w.total for w in walkers], result.values)
        self.assertEqual(len(double.allocated_sizes), 2)
        self.assertEqual(plan.payload_bytes(), 16 * 12 + 28 * 4)
        self.assertEqual(double.stack, [0x1234])
        nodes[0].value = 101.0
        batch = self.gpu.pack_walkers(self.schema, walkers, starts)
        session.execute(batch.buffers)
        self.assertEqual(batch.buffers.results.tolist(), [112, 40, 68, 96])
        self.assertEqual(len(double.allocated_sizes), 2)
        session.close()
        session.close()
        self.assertFalse(double.allocations or double.contexts or double.modules)
        self.assertIsNone(double.callback_error)

    def test_arena_growth_then_smaller_batches_keep_capacity(self):
        double, session = self.driver()
        for count in (1, 33, 257, 2):
            buffers = self.memory.chain_buffers([2.0], [-1], [0] * count, [1.0] * count)
            session.execute(buffers)
            self.assertEqual(buffers.results.tolist(), [3.0] * count)
            self.assertEqual(buffers.status.tolist(), [0] * count)
        self.assertEqual(len(double.allocated_sizes), 4)
        self.assertEqual(len(double.allocations), 2)
        self.assertEqual(session.plan.walker_layout.capacity, 512)
        self.assertEqual(double.launches[2], (3, 128, 1, 257))

    def test_cuda_failure_releases_resources_without_copyback(self):
        for which in ('fail_launch', 'fail_sync', 'fail_alloc'):
            with self.subTest(which=which):
                double, session = self.driver()
                setattr(double, which, True)
                walkers = [self.chain.ChainSum(total=7.0)]
                batch = self.gpu.pack_walkers(self.schema, walkers, [self.chain.Cell(value=3.0)])
                with self.assertRaises(self.cuda.CudaError):
                    session.execute(batch.buffers)
                self.assertEqual(walkers[0].total, 7.0)
                self.assertFalse(double.allocations or double.contexts or double.modules)
                self.assertEqual(double.stack, [0x1234])
                with self.assertRaisesRegex(RuntimeError, 'closed'):
                    session.execute(batch.buffers)

    def test_partial_growth_memory_failure_preserves_actual_capacity(self):
        double, session = self.driver()
        small = self.memory.chain_buffers([2.0], [-1], [0], [1.0])
        session.execute(small)
        double.free_bytes = 3000
        large = self.memory.chain_buffers([2.0] * 65, [-1] * 65, [0] * 65, [1.0] * 65)
        with self.assertRaises(MemoryError):
            session.execute(large)
        self.assertFalse(session.closed)
        self.assertEqual(session.graph_arena.capacity, 128)
        plan = session.execute(small)
        self.assertEqual(plan.graph_layout.capacity, 128)
        self.assertEqual(plan.allocated_bytes(), sum(size for _, size in double.allocations.values()))
        self.assertEqual(small.results.tolist(), [3.0])
    def test_failure_status_and_concurrent_state_change_prevent_publication(self):
        double, session = self.driver()
        for corrupt in (True, False):
            walkers = [self.chain.ChainSum(total=7.0), self.chain.ChainSum(total=9.0)]
            batch = self.gpu.pack_walkers(self.schema, walkers, [self.chain.Cell(value=3.0)] * 2)
            double.corrupt_status = corrupt
            double.on_sync = None if corrupt else lambda: setattr(walkers[1], 'total', 99.0)
            plan = session.execute(batch.buffers)
            with self.assertRaises(RuntimeError):
                self.gpu.publish_results(self.schema, batch, plan, '', 0)
            self.assertEqual(walkers[0].total, 7.0)
            self.assertEqual(walkers[1].total, 9.0 if corrupt else 99.0)

    def test_invalid_graphs_and_walker_lists_are_rejected(self):
        nodes = self.nodes()
        w = self.chain.ChainSum()
        cases = [([w, w], [nodes[0], nodes[3]]), ([w], []), ([object()], [nodes[0]]), ([w], [object()])]
        for walkers, starts in cases:
            with self.assertRaises((TypeError, ValueError)):
                self.gpu.pack_walkers(self.schema, walkers, starts)
        self.jac.connect(nodes[0], nodes[5], self.chain.Next)
        with self.assertRaisesRegex(ValueError, 'at most one'):
            self.gpu.pack_walkers(self.schema, [w], [nodes[0]])
        self.jac.connect(nodes[8], nodes[6], self.chain.Next)
        with self.assertRaisesRegex(ValueError, 'cycle'):
            self.gpu.pack_walkers(self.schema, [w], [nodes[6]])
        nodes[9].__jac__.destroyed = True
        with self.assertRaisesRegex(ValueError, 'live'):
            self.gpu.pack_walkers(self.schema, [w], [nodes[9]])
        w.__jac__.next = [nodes[3].__jac__]
        with self.assertRaisesRegex(ValueError, 'queued'):
            self.gpu.pack_walkers(self.schema, [w], [nodes[3]])

    def test_empty_batch_and_empty_traversal(self):
        self.assertFalse(self.gpu.run_walkers([], []).gpu_executed)
        batch = self.gpu.pack_walkers(self.schema, [self.chain.ChainSum(total=-0.0)], [None])
        double, session = self.driver()
        plan = session.execute(batch.buffers)
        self.assertEqual(plan.graph_layout.nbytes, 0)
        self.assertEqual(len(double.allocations), 1)
        self.assertEqual(bytes(batch.buffers.initial), bytes(batch.buffers.results))
        self.assertEqual(batch.buffers.status.tolist(), [0])

    def test_memory_regions_are_aligned_disjoint_and_capacity_bounded(self):
        for n in (0, 1, 31, 32, 33, 1024, 100001):
            plan = self.memory.memory_plan(n, n)
            for layout, sizes in ((plan.graph_layout, [8, 8]), (plan.walker_layout, [8, 8, 8, 4])):
                self.assertTrue(all(offset % 256 == 0 for offset in layout.offsets))
                self.assertGreaterEqual(layout.capacity, n)
                self.assertLessEqual(layout.capacity, max(0, n * 2))
                for i, (offset, size) in enumerate(zip(layout.offsets, sizes)):
                    end = offset + layout.capacity * size
                    self.assertLessEqual(end, layout.offsets[i + 1] if i + 1 < len(sizes) else layout.nbytes)

    def test_public_runtime_and_missing_driver(self):
        nodes = self.nodes()
        walkers = [self.chain.ChainSum(total=4.0)]
        runtime = self.gpu.GpuWalkerRuntime(self.chain.ChainSum)
        self.addCleanup(runtime.close)
        double, session = self.driver()
        runtime.session = session
        result = runtime.run_walkers(walkers, [nodes[0]])
        self.assertEqual(result.values, [10.0])
        self.assertEqual(walkers[0].total, 10.0)
        runtime.close()
        with self.assertRaisesRegex(RuntimeError, 'open'):
            runtime.prepare(walkers, [nodes[0]])
        with patch.object(c, 'CDLL', side_effect=OSError('missing')):
            with self.assertRaisesRegex(self.cuda.CudaError, 'No CPU fallback'):
                self.cuda.CudaDriver()


if __name__ == '__main__':
    unittest.main()
