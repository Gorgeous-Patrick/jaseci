"""Read-only task dependencies for a bounded GPU CSR walker."""

node Task {
    has cost: int,
        severity: int;
}

edge DependsOn {}

walker DependencyExposure {
    has total_cost: int = 0,
        high_risk: int = 0,
        visits: int = 0,
        threshold: int = 0;

    can inspect with Task entry {
        self.visits += 1;
        self.total_cost += here.cost;
        if here.severity >= self.threshold {
            self.high_risk += 1;
        }
        visit [->:DependsOn:->];
    }
}
