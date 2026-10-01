"""Run 1,000 walkers on a branching shared graph; check against serial Jac."""

import from csr_graph { Vertex, Link, GraphSum, GraphTrace }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

glob walker_count = 1000;

with entry {
    nodes = [Vertex(value=i + 1) for i in range(5)];
    nodes[0] +>:Link():+> nodes[1];
    nodes[0] +>:Link():+> nodes[2];
    nodes[1] +>:Link():+> nodes[3];
    nodes[2] +>:Link():+> nodes[3];
    nodes[2] +>:Link():+> nodes[4];
    nodes[3] +>:Link():+> nodes[4];
    starts = [nodes[i % len(nodes)] for i in range(walker_count)];
    walkers = [GraphSum(total=i) for i in range(walker_count)];
}

glob expected: list[int] = [];
with entry {
    for i in range(walker_count) {
        reference = GraphSum(total=i);
        starts[i] spawn reference;
        expected.append(reference.total);
    }
    with GpuWalkerRuntime(
        GraphSum, graph_format="csr", queue_capacity=16, max_visits=100
    ) as gpu {
        packed = gpu.prepare(walkers, starts);
        result = gpu.run_walkers(walkers, starts);
        assert result.values == expected;
        assert [w.total for w in walkers] == expected;
        assert result.status == [0] * walker_count;
        print("GPU:", result.gpu_name);
        print("GPU executed:", result.gpu_executed);
        print("Storage: CSR (experimental)");
        print("Walkers:", walker_count);
        print("Shared nodes:", len(packed.nodes));
        print("CSR adjacency entries:", result.memory.edge_count);
        print("Payload bytes (including queues):", result.memory.payload_bytes());
        print("Allocated bytes:", result.memory.allocated_bytes());
        print("First 5 sums:", result.values[:5]);
        print("Last 5 sums:", result.values[-5:]);
    }
    reference_trace = GraphTrace();
    nodes[0] spawn reference_trace;
    trace = GraphTrace();
    with GpuWalkerRuntime(GraphTrace, graph_format="csr", queue_capacity=16) as gpu {
        result = gpu.run_walkers([trace], [nodes[0]]);
        assert trace.total == reference_trace.total == 12344555;
        print("Visit order checksum:", trace.total);
    }
    print("PASS: all results and visit order match serial Jac");
}
