"""Run batched subtree queries on CUDA and verify every result with serial Jac.

jac run jac/examples/gpu/subtree_query_run.jac --nodes 255 --queries 1024
"""

import argparse;
import time;
import from subtree_query { SubtreeQuery }
import from subtree_query_data { make_tree }
import from jaclang.runtime.gpu { GpuWalkerRuntime }

with entry {
    parser = argparse.ArgumentParser(description="Batched Jac subtree queries on CUDA");
    parser.add_argument("--nodes", type=int, `default=255, help="Number of tree nodes");
    parser.add_argument("--queries", type=int, `default=1024, help="Number of independent walkers");
    parser.add_argument("--device", type=int, `default=0, help="CUDA device index");
    options = parser.parse_args();
    if options.nodes < 1 or options.queries < 1 {
        parser.error("--nodes and --queries must be positive");
    }

    # A small, easily checked example: one shared tree, different queries.
    small = make_tree([100, 50, 200, 20, 150, 80, 250],
        [False, True, False, False, True, False, True]);
    small_roots = [0, 1, 2, 3];
    small_walkers = [SubtreeQuery(threshold=100) for i in small_roots];
    with GpuWalkerRuntime(SubtreeQuery, graph_format="csr", device=options.device,
        queue_capacity=8, max_visits=7) as gpu {
        result = gpu.run_walkers(small_walkers, [small[i] for i in small_roots]);
        assert result.gpu_executed;
        assert result.fields["count"] == [4, 1, 2, 0];
        assert result.fields["total"] == [700, 150, 450, 0];
        assert result.fields["has_alert"] == [True, True, True, False];
        print("Small example (threshold=100):");
        for (root_index, query) in zip(small_roots, small_walkers) {
            print(f"  root={root_index}: count={query.count}, total={query.total}, alert={query.has_alert}");
        }
    }

    begin = time.perf_counter();
    nodes = make_tree([(i * 73 + 19) % 1000 for i in range(options.nodes)],
        [i % 11 == 0 for i in range(options.nodes)]);
    build_ms = (time.perf_counter() - begin) * 1000;
    root_indices = [i % min(options.nodes, 31) for i in range(options.queries)];
    thresholds = [(i * 37) % 1001 for i in range(options.queries)];
    walkers = [SubtreeQuery(threshold=value) for value in thresholds];
    starts = [nodes[i] for i in root_indices];

    begin = time.perf_counter();
    references: list[SubtreeQuery] = [];
    for (start, threshold) in zip(starts, thresholds) {
        reference = SubtreeQuery(threshold=threshold);
        start spawn reference;
        references.append(reference);
    }
    reference_ms = (time.perf_counter() - begin) * 1000;

    # The setup timer includes source analysis and PTX compilation.
    begin = time.perf_counter();
    with GpuWalkerRuntime(SubtreeQuery, graph_format="csr", device=options.device,
        queue_capacity=options.nodes, max_visits=options.nodes) as gpu {
        setup_ms = (time.perf_counter() - begin) * 1000;
        begin = time.perf_counter();
        result = gpu.run_walkers(walkers, starts);
        batch_ms = (time.perf_counter() - begin) * 1000;
        assert result.gpu_executed;
        assert result.status == [0] * options.queries;
        for (actual, reference) in zip(walkers, references) {
            assert actual.count == reference.count;
            assert actual.total == reference.total;
            assert actual.has_alert == reference.has_alert;
            assert actual.visited == reference.visited;
            assert actual.threshold == reference.threshold;
        }
        print("GPU:", result.gpu_name);
        print(f"Shared tree: {result.memory.node_count} nodes, {result.memory.edge_count} edges");
        print(f"Independent queries: {options.queries}");
        print("Total node visits:", sum(w.visited for w in walkers));
        print(f"CPU graph construction: {build_ms:.3f} ms");
        print(f"Serial validation reference: {reference_ms:.3f} ms");
        print(f"Runtime setup / PTX compilation: {setup_ms:.3f} ms");
        print(f"GPU batch (packing + transfers + execution + copyback): {batch_ms:.3f} ms");
        print("Device payload bytes:", result.memory.payload_bytes());
        print("First 5 queries:");
        for i in range(min(5, len(walkers))) {
            q = walkers[i];
            print(f"  root={root_indices[i]}, threshold={q.threshold}: visited={q.visited}, count={q.count}, total={q.total}, alert={q.has_alert}");
        }
        print("PASS: every GPU query matches serial Jac");
    }
}
