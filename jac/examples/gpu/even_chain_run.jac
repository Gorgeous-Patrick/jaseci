"""Run 1,000 integer walkers on CUDA and compare every result with serial Jac."""

import from even_chain { IntCell, IntNext, EvenSum }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob walker_count = 1000,
     chain_length = 6;

with entry {
    cells = [IntCell(value=i - 3) for i in range(walker_count * chain_length)];
    for base in range(0, len(cells), chain_length) {
        for hop in range(chain_length - 1) {
            cells[base + hop] +>:IntNext():+> cells[base + hop + 1];
        }
    }
    starts = cells[::chain_length];
    walkers = [EvenSum(total=i) for i in range(walker_count)];
}

glob expected: list[int] = [];

with entry {
    for i in range(walker_count) {
        reference = EvenSum(total=i);
        starts[i] spawn reference;
        expected.append(reference.total);
    }
    with GpuWalkerRuntime(EvenSum) as gpu {
        result = gpu.run_walkers(walkers, starts);
        assert result.values == expected;
        assert [w.total for w in walkers] == expected;
        assert all(type(w.total) is int for w in walkers);
        assert result.status == [0] * walker_count;
        print("GPU:", result.gpu_name);
        print("GPU executed:", result.gpu_executed);
        print("Walkers:", walker_count);
        print("First 5 even sums:", result.values[:5]);
        print("Last 5 even sums:", result.values[-5:]);
        print("PASS: all results match serial Jac");
    }
}
