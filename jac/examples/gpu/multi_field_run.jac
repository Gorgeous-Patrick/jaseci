import from multi_field { Position, Sample, Link, WeightedSum }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

with entry {
    nodes = [
        Sample(value=i + 2, weight=i + 1, position=Position(x=i, y=10 * i))
        for i in range(5)
    ];
    nodes[0] +>:Link():+> nodes[1];
    nodes[0] +>:Link():+> nodes[2];
    nodes[1] +>:Link():+> nodes[3];
    nodes[2] +>:Link():+> nodes[3];
    nodes[3] +>:Link():+> nodes[4];

    walkers = [WeightedSum(total=i) for i in range(1000)];
    starts = [nodes[i % len(nodes)] for i in range(len(walkers))];
}

glob expected: list[int] = [];
with entry {
    for i in range(len(walkers)) {
        reference = WeightedSum(total=i);
        starts[i] spawn reference;
        expected.append(reference.total);
    }
    with GpuWalkerRuntime(WeightedSum, graph_format="csr", queue_capacity=16) as gpu {
        result = gpu.run_walkers(walkers, starts);
        assert result.values == expected;
        assert [w.total for w in walkers] == expected;
        assert result.gpu_executed;
        print(f"GPU: {result.gpu_name}");
        print(f"Walkers: {len(walkers)}");
        print(f"Node columns: {gpu.schema.field_paths()}");
        print(f"Payload bytes: {result.memory.payload_bytes()}");
        print(f"First 5 sums: {result.values[:5]}");
        print("PASS: all multi-field GPU results match serial Jac");
    }
}
