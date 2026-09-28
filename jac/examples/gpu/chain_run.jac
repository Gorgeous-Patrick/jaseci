"""Run 1,000 actual Jac walker instances on CUDA using the batch runtime."""

import from chain { Cell, Next, ChainSum }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob walker_count = 1000;

with entry {
    cells = [Cell(value=float(i + 1)) for i in range(3 * walker_count)];
    for base in range(0, len(cells), 3) {
        cells[base] +>:Next():+> cells[base + 1];
        cells[base + 1] +>:Next():+> cells[base + 2];
    }
    walkers = [ChainSum(total=float(i * 10)) for i in range(walker_count)];
    starts = [cells[3 * i] for i in range(walker_count)];
    expected = [float(19 * i + 6) for i in range(walker_count)];
    with GpuWalkerRuntime(ChainSum) as gpu {
        packed = gpu.prepare(walkers, starts);
        plan = packed.memory_plan();
        print("Walkers:", walker_count);
        print("Nodes:", len(packed.nodes));
        print("Payload bytes:", plan.payload_bytes());
        print("Allocated bytes:", plan.allocated_bytes());
        result = gpu.run_walkers(walkers, starts);
        print("GPU:", result.gpu_name);
        print("GPU executed:", result.gpu_executed);
        print("First 5 totals:", result.values[:5]);
        print("Last 5 totals:", result.values[-5:]);
        assert result.values == expected;
        assert [w.total for w in walkers] == expected;
        assert result.status == [0] * walker_count;
        print("PASS");
    }
}
