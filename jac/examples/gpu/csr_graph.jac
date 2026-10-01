"""Numeric walkers for the experimental read-only CSR graph backend."""

node Vertex {
    has value: int;
}

edge Link {}

walker GraphSum {
    has total: int = 0;

    can step with Vertex entry {
        self.total += here.value;
        visit [->:Link:->];
    }
}

walker GraphTrace {
    has total: int = 0;

    can step with Vertex entry {
        self.total = self.total * 10 + here.value;
        visit [->:Link:->];
    }
}

walker GraphModulo {
    has total: int = 1;

    can step with Vertex entry {
        self.total = here.value % self.total;
        visit [->:Link:->];
    }
}
