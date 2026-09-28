"""Run four actual Jac walker instances on CUDA using the batch runtime."""

import from chain { Cell, Next, ChainSum }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

with entry {
    cells = [Cell(value=float(i + 1)) for i in range(12)];
    for base in (0, 3, 6, 9) {
        cells[base] +>:Next():+> cells[base + 1];
        cells[base + 1] +>:Next():+> cells[base + 2];
    }
    walkers = [ChainSum(total=float(i * 10)) for i in range(4)];
    starts = [cells[i] for i in (0, 3, 6, 9)];
    with GpuWalkerRuntime(ChainSum) as gpu {
        packed = gpu.prepare(walkers, starts);
        print("Node slot values:", packed.buffers.values.tolist());
        plan = packed.memory_plan();
        print("Payload bytes:", plan.payload_bytes());
        print("Allocated bytes:", plan.allocated_bytes());
        result = gpu.run_walkers(walkers, starts);
        print("GPU:", result.gpu_name);
        print("GPU executed:", result.gpu_executed);
        print("Walker totals:", [w.total for w in walkers]);
        assert result.values == [6.0, 25.0, 44.0, 63.0];
        assert result.status == [0, 0, 0, 0];
        print("PASS");
    }
}
