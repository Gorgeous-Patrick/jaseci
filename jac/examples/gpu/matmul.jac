"""One GPU walker computes one matrix output's dot product."""

node ProductTerm {
    has left: float, right: float;
}

edge NextTerm {}

walker DotProduct {
    has total: float = 0.0;

    can multiply with ProductTerm entry {
        self.total += here.left * here.right;
        visit [->:NextTerm:->];
    }
}
