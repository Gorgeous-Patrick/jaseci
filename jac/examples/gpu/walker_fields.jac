obj Metrics {
    has weighted: int = 0,
        last: int = 0;
}

node Sample {
    has value: int,
        weight: int;
}

edge Link {}

walker Statistics {
    has total: int = 0,
        count: int = 0,
        metrics: Metrics = Metrics();

    can step with Sample entry {
        self.total += here.value;
        self.count += 1;
        if here.value >= 0 {
            self.metrics.weighted += self.total * here.weight;
            self.metrics.last = self.metrics.weighted - self.count;
        } elif here.value == -1 {
            self.metrics.last = self.total;
            self.metrics.weighted -= self.count;
        } else {
            self.metrics.last = here.value;
        }
        visit [->:Link:->];
    }
}
