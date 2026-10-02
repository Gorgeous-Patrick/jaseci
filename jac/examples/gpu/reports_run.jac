import from reports { Sample, Link, Collector }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

with entry {
    nodes = [Sample(value=2), Sample(value=-1), Sample(value=3)];
    nodes[0] +>:Link():+> nodes[1];
    nodes[0] +>:Link():+> nodes[2];
    nodes[1] +>:Link():+> nodes[2];
    walkers = [Collector(total=i) for i in range(1000)];
    starts = [nodes[i % len(nodes)] for i in range(len(walkers))];
    expected: list[Collector] = [];
    for i in range(len(walkers)) {
        reference = Collector(total=i);
        starts[i] spawn reference;
        expected.append(reference);
    }
    with GpuWalkerRuntime(
        Collector, graph_format="csr", queue_capacity=16, report_capacity=16
    ) as gpu {
        result = gpu.run_walkers(walkers, starts);
        assert result.gpu_executed;
        for (actual, reference) in zip(walkers, expected) {
            assert actual.total == reference.total;
            assert actual.reports == reference.reports;
        }
        print(f"GPU: {result.gpu_name}");
        print(f"First walker reports: {walkers[0].reports}");
        print("PASS: every report and final state matches serial Jac");
    }
}
