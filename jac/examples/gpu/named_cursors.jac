node Scalar { has value: int; }
node Other { has value: int; }
edge RowNext {}
edge ColumnNext {}
edge ThirdNext {}
walker Dot {
    cursor a, b;
    has total: int = 0;
    can multiply with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}
walker Three {
    cursor a, b, c;
    has total: int = 0;
    can add with (c: Scalar entry, a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value + here[b].value + here[c].value;
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
        visit[c] [->:ThirdNext:->];
    }
}
walker Conditional {
    cursor a, b;
    has total: int = 0;
    can add with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        if here[a].value > 0 { visit[a] [->:RowNext:->]; }
        if self.total < 100 { visit[b] [->:ColumnNext:->]; }
    }
}
walker StopOne {
    cursor a, b;
    has total: int = 0;
    can add with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        visit[a] [->:RowNext:->];
    }
}
walker LoopDot {
    cursor a, b;
    has total: int = 0;
    can add with (a: Scalar entry, b: Scalar entry) {
        remaining = here[a].value;
        while remaining > 0 { self.total += here[b].value; remaining -= 1; }
        for i in range(here[b].value) { self.total += i; }
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}
walker ReportDot {
    cursor a, b;
    has total: int = 0;
    can add with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        report self.total;
        report here[a].value > 0;
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}

def build_matmul(a: list[list[int]], b: list[list[int]]) -> tuple[list[Dot], list[dict[str, Scalar]], list[list[Scalar]]] {
    assert len(a) > 0 and len(b) > 0 and len(b[0]) > 0;
    inner = len(b);
    assert all(len(row) == inner for row in a);
    width = len(b[0]);
    assert all(len(row) == width for row in b);
    left = [[Scalar(value=v) for v in row] for row in a];
    right = [[Scalar(value=b[k][j]) for k in range(inner)] for j in range(width)];
    for row in left {
        for k in range(inner - 1) { row[k] +>:RowNext():+> row[k + 1]; }
    }
    for col in right {
        for k in range(inner - 1) { col[k] +>:ColumnNext():+> col[k + 1]; }
    }
    walkers: list[Dot] = [];
    starts: list[dict[str, Scalar]] = [];
    output = [[Scalar(value=0) for j in range(width)] for i in range(len(a))];
    for i in range(len(a)) {
        for j in range(width) {
            walkers.append(Dot());
            starts.append({"a": left[i][0], "b": right[j][0]});
        }
    }
    return (walkers, starts, output);
}
with entry {
    (walkers, starts, output) = build_matmul([[1, 2, 3], [4, 5, 6]], [[7, 8], [9, 10], [11, 12]]);
    for i in range(len(walkers)) { starts[i] spawn walkers[i]; }
    for i in range(len(output)) {
        for j in range(len(output[i])) { output[i][j].value = walkers[i * len(output[i]) + j].total; }
    }
    print([[nd.value for nd in row] for row in output]);
}
