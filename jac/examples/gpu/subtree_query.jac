"""Independent threshold queries over a shared, read-only tree."""

node Item {
    has amount: int, alert: bool;
}

edge Child {}

walker SubtreeQuery {
    has count: int = 0,
        total: int = 0,
        has_alert: bool = False,
        visited: int = 0,
        threshold: int = 0;

    can inspect with Item entry {
        self.visited += 1;
        if here.amount >= self.threshold {
            self.count += 1;
            self.total += here.amount;
            self.has_alert = self.has_alert or here.alert;
        }
        visit [->:Child:->];
    }
}
