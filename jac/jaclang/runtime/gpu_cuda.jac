import ctypes as c;
import sys;
import from array { array }
import from threading { get_ident }
import from logging { getLogger }
import from jaclang.runtime.gpu_memory { ChainBuffers, GpuMemoryPlan, memory_plan }

glob logger = getLogger(__name__);

class CudaError(RuntimeError) {}

obj CudaDriver {
    has library: any = None;

    def postinit {
        if c.sizeof(c.c_void_p) != 8
            or sys.byteorder != 'little'
            or not sys.platform.startswith('linux') {
            raise CudaError("The CUDA launcher requires little-endian 64-bit Linux");
        }
        if self.library is None {
            try {
                self.library = c.CDLL('libcuda.so.1');
            } except OSError as error {
                raise CudaError(
                    "Cannot load libcuda.so.1; run with an accessible NVIDIA driver. No CPU fallback."
                ) from error;
            }
        }
        (p, u, i, sz, ptr) = (c.c_void_p, c.c_uint, c.c_int, c.c_size_t, c.c_uint64);
        signatures = {
            'cuInit': [u],
            'cuDeviceGetCount': [c.POINTER(i)],
            'cuDeviceGet': [c.POINTER(i), i],
            'cuDeviceGetName': [p, i, i],
            'cuDeviceGetAttribute': [c.POINTER(i), i, i],
            'cuDriverGetVersion': [c.POINTER(i)],
            'cuGetErrorName': [i, c.POINTER(c.c_char_p)],
            'cuGetErrorString': [i, c.POINTER(c.c_char_p)],
            'cuCtxCreate_v2': [c.POINTER(p), u, i],
            'cuCtxDestroy_v2': [p],
            'cuCtxPushCurrent_v2': [p],
            'cuCtxPopCurrent_v2': [c.POINTER(p)],
            'cuCtxSynchronize': [],
            'cuModuleLoadDataEx': [c.POINTER(p), p, u, c.POINTER(i), c.POINTER(p)],
            'cuModuleGetFunction': [c.POINTER(p), p, c.c_char_p],
            'cuModuleUnload': [p],
            'cuFuncGetAttribute': [c.POINTER(i), i, p],
            'cuMemAlloc_v2': [c.POINTER(ptr), sz],
            'cuMemFree_v2': [ptr],
            'cuMemGetInfo_v2': [c.POINTER(sz), c.POINTER(sz)],
            'cuMemcpyHtoD_v2': [ptr, p, sz],
            'cuMemcpyDtoH_v2': [p, ptr, sz],
            'cuLaunchKernel': [p, u, u, u, u, u, u, u, p, c.POINTER(p), c.POINTER(p)]
        };
        for (name, types) in signatures.items() {
            fn = getattr(self.library, name);
            fn.argtypes = types;
            fn.restype = i;
        }
    }

    def call(name: str, *args: any) {
        code = getattr(self.library, name)(*args);
        if code {
            (label, message) = (c.c_char_p(), c.c_char_p());
            self.library.cuGetErrorName(code, c.byref(label));
            self.library.cuGetErrorString(code, c.byref(message));
            tag = (label.value or b'CUDA_ERROR').decode(errors='replace');
            detail = (message.value or b'').decode(errors='replace');
            raise CudaError(f"{name}: {tag} ({code}): {detail}");
        }
    }

    def cleanup(name: str, *args: any) {
        try {
            self.call(name, *args);
        } except CudaError as error {
            logger.warning(f"CUDA cleanup: {error}");
        }
    }

    def attribute(device: int, attribute: int) -> int {
        value = c.c_int();
        self.call('cuDeviceGetAttribute', c.byref(value), attribute, device);
        return value.value;
    }
}

obj DeviceArena {
    has address: int = 0,
        nbytes: int = 0,
        capacity: int = 0;

    def reserve(driver: CudaDriver, nbytes: int, capacity: int) {
        if nbytes <= self.nbytes {
            self.capacity = max(self.capacity, capacity);
            return;
        }
        (free, total) = (c.c_size_t(), c.c_size_t());
        driver.call('cuMemGetInfo_v2', c.byref(free), c.byref(total));
        if nbytes > free.value {
            raise MemoryError(
                f"GPU arena growth needs {nbytes} free bytes; {free.value} available (old allocation retained during growth)"
            );
        }
        new_address = c.c_uint64();
        driver.call('cuMemAlloc_v2', c.byref(new_address), nbytes);
        old_address = self.address;
        self.address = new_address.value;
        self.nbytes = nbytes;
        self.capacity = capacity;
        if old_address {
            driver.call('cuMemFree_v2', old_address);
        }
    }

    def close(driver: CudaDriver) {
        if self.address {
            driver.cleanup('cuMemFree_v2', self.address);
            self.address = 0;
            self.nbytes = 0;
            self.capacity = 0;
        }
    }
}

obj CudaSession {
    has ptx: str,
        kernel_name: str,
        device: int = 0,
        block_size: int = 128,
        driver: CudaDriver | None = None,
        context: any = None,
        module: any = None,
        function: any = None,
        graph_arena: DeviceArena = DeviceArena(),
        walker_arena: DeviceArena = DeviceArena(),
        plan: GpuMemoryPlan = memory_plan(0, 0),
        gpu_name: str = '',
        driver_version: int = 0,
        max_grid: int = 0,
        owner_thread: int = 0,
        closed: bool = False;

    def postinit {
        self.owner_thread = get_ident();
        if self.device < 0 or not 1 <= self.block_size <= 1024 {
            raise ValueError("Invalid CUDA device or block size");
        }
        if self.driver is None {
            self.driver = CudaDriver();
        }
        d = self.driver;
        d.call('cuInit', 0);
        (count, dev, version) = (c.c_int(), c.c_int(), c.c_int());
        d.call('cuDeviceGetCount', c.byref(count));
        if self.device >= count.value {
            raise CudaError(
                f"CUDA device {self.device} unavailable; {count.value} devices visible"
            );
        }
        d.call('cuDeviceGet', c.byref(dev), self.device);
        if d.attribute(dev.value, 75) < 7 {
            raise CudaError(
                "This PTX prototype requires compute capability 7.0 or newer"
            );
        }
        if self.block_size
            > min(d.attribute(dev.value, 1), d.attribute(dev.value, 2)) {
            raise ValueError("CUDA block size exceeds the device limit");
        }
        self.max_grid = d.attribute(dev.value, 5);
        name = c.create_string_buffer(256);
        d.call('cuDeviceGetName', name, len(name), dev);
        self.gpu_name = name.value.decode();
        d.call('cuDriverGetVersion', c.byref(version));
        self.driver_version = version.value;
        self.context = c.c_void_p();
        d.call('cuCtxCreate_v2', c.byref(self.context), 0, dev);
        try {
            self.module = c.c_void_p();
            image = c.create_string_buffer(self.ptx.encode());
            errors = c.create_string_buffer(8192);
            options = (c.c_int * 3)(5, 6, 8);
            values = (c.c_void_p * 3)(c.addressof(errors), len(errors), 0);
            try {
                d.call(
                    'cuModuleLoadDataEx',
                    c.byref(self.module),
                    image,
                    3,
                    options,
                    values
                );
            } except CudaError as error {
                raise CudaError(
                    f"{error}\nPTX JIT: {errors.value.decode(errors='replace')}"
                ) from error;
            }
            self.function = c.c_void_p();
            d.call(
                'cuModuleGetFunction',
                c.byref(self.function),
                self.module,
                self.kernel_name.encode()
            );
            limit = c.c_int();
            d.call('cuFuncGetAttribute', c.byref(limit), 0, self.function);
            if self.block_size > limit.value {
                raise ValueError(
                    f"Kernel supports at most {limit.value} threads per block"
                );
            }
            popped = c.c_void_p();
            d.call('cuCtxPopCurrent_v2', c.byref(popped));
        } except BaseException {
            d.cleanup('cuCtxDestroy_v2', self.context);
            self.closed = True;
            raise;
        }
    }

    def check_thread {
        if self.closed {
            raise RuntimeError("CUDA session is closed");
        }
        if get_ident() != self.owner_thread {
            raise RuntimeError("Use the CUDA session on its creating thread");
        }
    }

    def transfer(name: str, address: int, buf: array) {
        assert self.driver is not None;
        size = len(buf) * buf.itemsize;
        if size {
            host = c.c_void_p(buf.buffer_info()[0]);
            if name == 'cuMemcpyHtoD_v2' {
                self.driver.call(name, address, host, size);
            } else {
                self.driver.call(name, host, address, size);
            }
        }
    }

    def execute(buffers: ChainBuffers) -> GpuMemoryPlan {
        self.check_thread();
        assert self.driver is not None;
        d = self.driver;
        n = len(buffers.values);
        m = len(buffers.heads);
        if not m {
            return memory_plan(
                n, m, self.graph_arena.capacity, self.walker_arena.capacity
            );
        }
        grid = (m + self.block_size - 1) // self.block_size;
        if grid > self.max_grid {
            raise ValueError("Walker batch exceeds the CUDA 1D grid limit");
        }
        d.call('cuCtxPushCurrent_v2', self.context);
        failed = False;
        try {
            plan = memory_plan(
                n, m, self.graph_arena.capacity, self.walker_arena.capacity
            );
            self.graph_arena.reserve(
                d, plan.graph_layout.nbytes, plan.graph_layout.capacity
            );
            self.walker_arena.reserve(
                d, plan.walker_layout.nbytes, plan.walker_layout.capacity
            );
            self.plan = plan;
            addresses = [
                self.graph_arena.address + offset
                for offset in plan.graph_layout.offsets
            ]
                + [
                    self.walker_arena.address + offset
                    for offset in plan.walker_layout.offsets
                ];
            for (address, buf) in zip(addresses, buffers.arrays()) {
                self.transfer('cuMemcpyHtoD_v2', address, buf);
            }
            arguments = [c.c_uint64(value) for value in [*addresses, n, m]];
            params = (c.c_void_p * len(arguments))(
                *(c.addressof(arg) for arg in arguments)
            );
            d.call(
                'cuLaunchKernel',
                self.function,
                grid,
                1,
                1,
                self.block_size,
                1,
                1,
                0,
                None,
                params,
                None
            );
            d.call('cuCtxSynchronize');
            self.transfer('cuMemcpyDtoH_v2', addresses[4], buffers.results);
            self.transfer('cuMemcpyDtoH_v2', addresses[5], buffers.status);
        } except CudaError {
            failed = True;
            raise;
        } finally {
            popped = c.c_void_p();
            d.cleanup('cuCtxPopCurrent_v2', c.byref(popped));
            if failed {
                self.close();
            }
        }
        return plan;
    }

    def close {
        if self.closed {
            return;
        }
        self.check_thread();
        assert self.driver is not None;
        d = self.driver;
        pushed = False;
        try {
            d.call('cuCtxPushCurrent_v2', self.context);
            pushed = True;
            self.walker_arena.close(d);
            self.graph_arena.close(d);
            d.cleanup('cuModuleUnload', self.module);
        } finally {
            if pushed {
                popped = c.c_void_p();
                d.cleanup('cuCtxPopCurrent_v2', c.byref(popped));
            }
            d.cleanup('cuCtxDestroy_v2', self.context);
            self.closed = True;
        }
    }
}
