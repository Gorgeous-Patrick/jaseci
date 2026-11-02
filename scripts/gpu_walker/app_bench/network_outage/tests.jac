"""CPU-only checks for outage link protection and the generated graph."""

import scripts.gpu_walker.app_bench.network_outage.benchmark as app;

test "backed up links stop the blast radius" {
    households = [0, 50, 0, 0];
    criticality = [0, 0, 3, 2];
    links = [[(1, False), (2, True)], [(3, False)], [], []];
    assert app.oracle(households, criticality, links, 0, 2) == ([50, 1, 3, 2], 1);
    assert app.oracle(households, criticality, links, 0, 3) == ([50, 0, 3, 3], 1);
}

test "generated snapshot and Jac walker agree with the raw topology" {
    (kinds, households, criticality, links, groups) = app.topology(1, 2, 2, 2);
    assert len(kinds) == 15;
    assert [len(group) for group in groups] == [1, 2, 4, 8];
    assert sum(len(row) for row in links) == 14;
    assert any(backed_up for row in links for (_, backed_up) in row);
    nodes = app.build_nodes(kinds, households, criticality, links);
    (roots, floors) = app.queries(groups, 8);
    for (root_id, floor) in zip(roots, floors) {
        probe = app.OutageImpact(priority_floor=floor);
        nodes[root_id] spawn probe;
        assert app.state(probe) == app.oracle(households, criticality, links, root_id, floor)[0];
    }
}
