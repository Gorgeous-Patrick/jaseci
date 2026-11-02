"""One Jac walker reduces one sparse row encoded as a small graph."""

node Entry {
    has value: int;
}

edge Member {}

walker RowSum {
    has total: int = 0,
        visited: int = 0;

    can accumulate with Entry entry {
        self.total += here.value;
        self.visited += 1;
        visit [->:Member:->];
    }
}
