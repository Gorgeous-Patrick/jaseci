"""CPU-only checks for monitoring graph construction and independent oracle."""

import scripts.gpu_walker.app_bench.hierarchy.benchmark as app;

test "monitoring oracle counts only qualifying devices" {
    children = [[1, 2], [3], [], []];
    kinds = [0, 1, 3, 3];
    readings = [0, 0, 5, -2];
    alerts = [0, 0, 1, 1];
    assert app.oracle(children, kinds, readings, alerts, 0, 0) == ([1, 5, 1, 4, 0], 2);
    assert app.oracle(children, kinds, readings, alerts, 1, -5) == ([1, -2, 1, 2, -5], 1);
}

test "monitoring builder creates a complete hierarchy" {
    nodes, children, kinds, readings, alerts, sites, buildings, devices = app.make_case(1, 2, 3);
    assert len(nodes) == 10;
    assert len(sites) == 1 and len(buildings) == 2 and len(devices) == 6;
    assert sum(len(row) for row in children) == len(nodes) - 1;
    assert [kinds[i] for i in sites] == [1];
    assert all(kinds[i] == 3 for i in devices);
    assert app.oracle(children, kinds, readings, alerts, sites[0], -501)[0][3] == 9;
}
