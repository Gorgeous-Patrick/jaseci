"""Read-only payment graph for bounded account fraud screening."""

node LedgerEntity {
    has kind: int,
        amount: int,
        cross_border: int,
        odd_hour: int,
        watchlisted: int;
}

edge Flow {}

walker FraudScreen {
    has threshold: int = 0,
        flagged_transfers: int = 0,
        flagged_amount: int = 0,
        watchlist_exposures: int = 0,
        visited: int = 0;

    can inspect with LedgerEntity entry {
        self.visited += 1;
        if here.kind == 2 {
            if here.amount >= self.threshold and (here.cross_border == 1 or here.odd_hour == 1) {
                self.flagged_transfers += 1;
                self.flagged_amount += here.amount;
            }
        } elif here.kind == 3 {
            if here.watchlisted == 1 {
                self.watchlist_exposures += 1;
            }
        }
        visit [->:Flow:->];
    }
}
