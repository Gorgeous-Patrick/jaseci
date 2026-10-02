"""Boolean node/state columns and ordered mixed boolean/numeric reports."""

obj Flags {
    has enabled: bool;
}

node Sample {
    has flags: Flags,
        value: int;
}

edge Link {}

walker Collector {
    has accepted: bool = False,
        total: int = 0,
        last: bool = True;

    can step with Sample entry {
        self.accepted = self.accepted or (here.flags.enabled and here.value > 0);
        self.last = not here.flags.enabled;
        report self.accepted;
        if here.flags.enabled and not self.last {
            self.total += here.value;
        }
        report self.total;
        report self.last;
        visit [->:Link:->];
    }
}
