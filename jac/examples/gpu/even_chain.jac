"""Sum even integer node values while visiting every node in a finite chain."""

node IntCell {
    has value: int;
}

edge IntNext {}

walker EvenSum {
    has total: int = 0;

    can step with IntCell entry {
        if here.value % 2 == 0 {
            self.total += here.value;
        }
        visit [->:IntNext:->];
    }
}
