"""Downstream network assets exposed by an upstream equipment failure."""

node NetworkAsset {
    has kind: int,
        households: int,
        criticality: int;
}

edge PropagatesTo {}

walker OutageImpact {
    has affected_households: int = 0,
        critical_sites: int = 0,
        visited: int = 0,
        priority_floor: int = 1;

    can assess with NetworkAsset entry {
        self.visited += 1;
        self.affected_households += here.households;
        if here.criticality >= self.priority_floor {
            self.critical_sites += 1;
        }
        visit [->:PropagatesTo:->];
    }
}
