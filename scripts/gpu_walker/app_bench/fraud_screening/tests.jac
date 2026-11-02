"""CPU-only checks for the payment screening oracle and graph builder."""

import scripts.gpu_walker.app_bench.fraud_screening.benchmark as app;
import from scripts.gpu_walker.app_bench.fraud_screening.model {
    Flow, FraudScreen, LedgerEntity
}

test "screening oracle counts flags and repeated recipient exposure" {
    rows = [[(1500, 1, 0, 0), (2000, 0, 0, 0), (800, 0, 1, 1)], []];
    assert app.oracle(rows, [1, 0], [1000, 500]) == [
        [1000, 1, 1500, 2, 7],
        [500, 0, 0, 0, 1]
    ];
}

test "screening graph has bounded two-hop fanout and shared payees" {
    starts, rows, watchlisted, thresholds, transfers = app.make_case(6, 3, 4);
    assert len(starts) == 6 and len(rows) == 6 and len(thresholds) == 6;
    assert len(watchlisted) == 3;
    assert transfers == sum(len(row) for row in rows);
    assert all(0 <= len(row) <= 4 for row in rows);
    assert all(0 <= recipient < 3 for row in rows for (_, _, _, recipient) in row);
    assert all(expected[4] <= 9 for expected in app.oracle(rows, watchlisted, thresholds));
}

test "Jac walker counts a shared recipient once per transfer" {
    account = LedgerEntity(kind=1, amount=0, cross_border=0, odd_hour=0,
                           watchlisted=0);
    first = LedgerEntity(kind=2, amount=1500, cross_border=1, odd_hour=0,
                         watchlisted=0);
    second = LedgerEntity(kind=2, amount=2000, cross_border=0, odd_hour=0,
                          watchlisted=0);
    recipient = LedgerEntity(kind=3, amount=0, cross_border=0, odd_hour=0,
                             watchlisted=1);
    account +>:Flow():+> first;
    account +>:Flow():+> second;
    first +>:Flow():+> recipient;
    second +>:Flow():+> recipient;
    walker = FraudScreen(threshold=1000);
    account spawn walker;
    assert app.output(walker) == [1000, 1, 1500, 2, 5];
}
