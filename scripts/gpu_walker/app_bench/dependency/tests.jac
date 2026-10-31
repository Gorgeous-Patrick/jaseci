"""Pure dependency-workload checks; these do not create Jac graphs or use CUDA."""

import unittest;
import from scripts.gpu_walker.app_bench.dependency.benchmark {
    case_data, oracle, query_indices
}

glob check: any = unittest.TestCase();

test "shared DAG arrivals remain distinct and bounds are exact" {
    children = [[1, 2], [3], [3], []];
    result, peak = oracle(children, [1, 2, 3, 5], [0, 3, 1, 4], 0, 2);
    check.assertEqual(result, [16, 3, 5, 2]);
    check.assertEqual(peak, 2);
    edges, costs, severities = case_data(4, 8, False);
    check.assertEqual(edges[0], [8, 9]);
    check.assertEqual(edges[1], [9, 10]);
    check.assertTrue(all(target > source for source, row in enumerate(edges) for target in row));
    check.assertEqual(len(costs), len(severities));
    starts, thresholds = query_indices(4, 8, 40);
    check.assertEqual(len(starts), len(thresholds));
    check.assertTrue(all(0 <= root < len(costs) for root in starts));
}
