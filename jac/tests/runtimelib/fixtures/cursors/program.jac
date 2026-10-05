node Scalar { has value: int; }
node Bridge { has label: str = "bridge"; }
node Other { has weight: int; }
node Active {
    has value: int = 0;
    can react with entry { self.value += 1; }
}
edge RowNext {}
edge ColumnNext {}
walker Dot {
    cursor a, b;
    has total: int = 0, pairs: list[tuple[int, int]] = [];
    can multiply with (a: Scalar entry, b: Scalar entry) {
        before_a = here[a]; before_b = here[b];
        self.total += here[a].value * here[b].value;
        self.pairs.append((here[a].value, here[b].value));
        visit[a] [->:RowNext:->];
        assert here[a] is before_a and here[b] is before_b;
        visit[b] [->:ColumnNext:->];
    }
}
walker Heterogeneous {
    cursor a, b;
    has total: int = 0, events: list[str] = [];
    can bridge with (a: Bridge entry, b: Other entry) {
        self.events.append(here[a].label);
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
    can multiply with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        self.events.append("product");
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}
walker StopOne {
    cursor a, b;
    has count: int = 0;
    can step with (a: Scalar entry, b: Scalar entry) {
        self.count += 1;
        visit[a] [->:RowNext:->];
    }
}
walker Ordered {
    cursor a, b;
    has events: list[str] = [], expected: tuple[int, int] = (0, 0);
    can first with (a: Scalar entry, b: Scalar entry) {
        self.events.append("first");
        self.expected = (here[a].value, here[b].value);
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
    can second with (b: Scalar entry, a: Scalar entry) {
        self.events.append("second");
        assert (here[a].value, here[b].value) == self.expected;
    }
}
walker Legacy {
    has events: list[str] = [];
    can start with entry { self.events.append("start"); }
    can step with Scalar entry {
        self.events.append("entry" + str(here.value));
        visit [->:RowNext:->];
    }
    can leave with Scalar exit { self.events.append("exit" + str(here.value)); }
    can finish with exit { self.events.append("finish"); }
}
walker InsertAndReport {
    cursor a, b;
    has events: list[tuple[int, int]] = [];
    can step with (a: Scalar entry, b: Scalar entry) {
        self.events.append((here[a].value, here[b].value));
        report here[a].value;
        if here[a].value == 1 {
            visit[a]:0: [->:RowNext:->];
        }
        visit[b] [->:ColumnNext:->] else { report -1; }
    }
}
walker FinishEarly {
    cursor a, b;
    has count: int = 0;
    can step with (a: Scalar entry, b: Scalar entry) {
        self.count += 1;
        disengage;
    }
}
node SubScalar(Scalar) {}
walker Three {
    cursor a, b, c;
    has total: int = 0;
    can step with (c: Scalar entry, b: Scalar entry, a: Scalar entry) {
        self.total += here[a].value + here[b].value + here[c].value;
    }
}
walker Nested {
    cursor a, b;
    has total: int = 0;
    can step with (a: Scalar entry, b: Scalar entry) {
        child = {"a": here[a], "b": here[b]} spawn Dot();
        self.total = child.total;
        # A child spawn cannot replace the parent's stable positions.
        report here[a].value;
        report here[b].value;
    }
}
walker ExplicitOrigins {
    cursor a, b;
    has pairs: list[tuple[int, int]] = [];
    can step with (a: Scalar entry, b: Scalar entry) {
        self.pairs.append((here[a].value, here[b].value));
        next_a = [here[a] ->:RowNext:->];
        visit[a] next_a;
        # Explicit receiver overrides b's default origin.
        visit[b] [here[a] ->:ColumnNext:->];
    }
}
walker ReturnAbility {
    cursor a, b;
    has count: int = 0;
    can first with (a: Scalar entry, b: Scalar entry) {
        self.count += 1;
        skip;
        self.count += 100;
    }
    can second with (a: Scalar entry, b: Scalar entry) { self.count += 1; }
}
walker EdgeTarget {
    cursor a, b;
    can step with (a: Scalar entry, b: Scalar entry) { visit[b] RowNext(); }
}
