"""A fresh walker follows a finite chain and accumulates its node values.

Compile with jac build chain.jac --as ptx --gpu-entry ChainSum.
The kernel takes an explicit batch over shared read-only graph arrays, with
private initial state and results per walker. GPU launching is not included.
"""

node Cell {
    has value: float;
}

edge Next {}

walker ChainSum {
    has total: float = 0.0;

    can step with Cell entry {
        self.total += here.value;
        visit [->:Next:->];
    }
}
