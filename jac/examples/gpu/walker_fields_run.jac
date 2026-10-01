import from walker_fields { Metrics, Sample, Link, Statistics }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

with entry {
    nodes = [Sample(value=i - 2, weight=i + 1) for i in range(5)];
    nodes[0] +>:Link():+> nodes[1];
    nodes[0] +>:Link():+> nodes[2];
    nodes[1] +>:Link():+> nodes[3];
    nodes[2] +>:Link():+> nodes[3];
    nodes[3] +>:Link():+> nodes[4];
    walkers = [Statistics(total=i, metrics=Metrics()) for i in range(1000)];
    starts = [nodes[i % len(nodes)] for i in range(len(walkers))];
}

glob expected: list[Statistics] = [];

with entry {
    for i in range(len(walkers)) {
        reference = Statistics(total=i, metrics=Metrics());
        starts[i] spawn reference;
        expected.append(reference);
    }
    with GpuWalkerRuntime(Statistics, graph_format="csr", queue_capacity=16) as gpu {
        result = gpu.run_walkers(walkers, starts);
        assert result.gpu_executed;
        assert result.fields["total"] == [w.total for w in expected];
        assert result.fields["count"] == [w.count for w in expected];
        assert result.fields["metrics.weighted"]
            == [w.metrics.weighted for w in expected];
        assert result.fields["metrics.last"] == [w.metrics.last for w in expected];
        for (actual, reference) in zip(walkers, expected) {
            assert actual.total == reference.total;
            assert actual.count == reference.count;
            assert actual.metrics.weighted == reference.metrics.weighted;
            assert actual.metrics.last == reference.metrics.last;
        }
        print(f"GPU: {result.gpu_name}");
        print(f"Walkers: {len(walkers)}");
        print(f"Walker columns: {gpu.schema.state_paths()}");
        print(f"First 5 totals: {result.values[:5]}");
        print("PASS: all four walker fields match serial Jac");
    }
}
