"""Numeric report snapshots from a read-only graph traversal."""

node Sample {
    has value: int;
}

edge Link {}

walker Collector {
    has total: int = 0;

    can step with Sample entry {
        report self.total;
        self.total += here.value;
        report self.total;
        if here.value > 0 {
            report here.value;
        }
        visit [->:Link:->];
    }
}
