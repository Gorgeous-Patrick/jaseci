"""Shared portfolio tree for thresholded device monitoring."""

node Asset {
    has kind: int, reading: int, alert: bool;
}

edge Child {}

walker Monitor {
    has count: int = 0,
        total: int = 0,
        has_alert: bool = False,
        visited: int = 0,
        threshold: int = 0;

    can inspect with Asset entry {
        self.visited += 1;
        if here.kind == 3 {
            if here.reading >= self.threshold {
                self.count += 1;
                self.total += here.reading;
                self.has_alert = self.has_alert or here.alert;
            }
        }
        visit [->:Child:->];
    }
}
