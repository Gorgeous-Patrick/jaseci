"""Run dynamic nested loops on CUDA and compare with serial Jac."""
import from loops { LoopCell, LoopNext, LoopSum }
import from jaclang.runtime.gpu { GpuWalkerRuntime }
with entry {
    cells = [LoopCell(value=i % 8) for i in range(128)];
    for i in range(0, len(cells), 2) { cells[i] +>:LoopNext():+> cells[i + 1]; }
    heads = cells[::2];
    walkers = [LoopSum(total=i) for i in range(len(heads))];
    expected: list[int] = [];
    for i in range(len(heads)) {
        reference = LoopSum(total=i);
        heads[i] spawn reference;
        expected.append(reference.total);
    }
    with GpuWalkerRuntime(LoopSum) as gpu {
        result = gpu.run_walkers(walkers, heads);
        assert result.values == expected;
        assert [w.total for w in walkers] == expected;
        assert result.status == [0] * len(walkers);
        print("GPU:", result.gpu_name);
        print("GPU executed:", result.gpu_executed);
        print("PASS: dynamic nested loops match serial Jac");
    }
}
