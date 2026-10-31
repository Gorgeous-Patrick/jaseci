"""CPU-only checks for the weighted event-chain workload."""

import from model {
    RiskScore, expected_scores, initial_score, make_workload
}

test "event-chain arithmetic oracle matches ordinary Jac traversal" {
    starts, nodes = make_workload(2, 3);
    assert len(starts) == 2 and len(nodes) == 6;
    expected = expected_scores(nodes, 2, 3);
    assert expected == [-24, 23];
    for lane in range(2) {
        walker = RiskScore(score=initial_score(lane));
        starts[lane] spawn walker;
        assert walker.score == expected[lane];
        assert walker.visited == 3;
    }
}
