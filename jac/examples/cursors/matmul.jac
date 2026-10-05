"""Shared scalar nodes: dot products follow A rows and B columns on Python CPU."""
node Scalar { has value: int; }
edge RowNext {}
edge ColumnNext {}
walker Product {
    cursor a, b;
    has output: Scalar;
    can accumulate with (a: Scalar entry, b: Scalar entry) {
        self.output.value += here[a].value * here[b].value;
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}
def multiply(a: list[list[int]], b: list[list[int]]) -> list[list[Scalar]] {
    assert a and b and a[0] and b[0];
    m = len(a); k = len(a[0]); n = len(b[0]);
    assert len(b) == k;
    assert all(len(row) == k for row in a);
    assert all(len(row) == n for row in b);
    left = [[Scalar(value=v) for v in row] for row in a];
    right = [[Scalar(value=v) for v in row] for row in b];
    for i in range(m) {
        for t in range(k - 1) { left[i][t] +>:RowNext():+> left[i][t + 1]; }
    }
    for j in range(n) {
        for t in range(k - 1) { right[t][j] +>:ColumnNext():+> right[t + 1][j]; }
    }
    outputs = [[Scalar(value=0) for j in range(n)] for i in range(m)];
    for i in range(m) {
        for j in range(n) {
            {"a": left[i][0], "b": right[0][j]} spawn Product(output=outputs[i][j]);
        }
    }
    # Nodes have one int field. The same input nodes serve every product walker.
    assert [[node.value for node in row] for row in left] == a;
    assert [[node.value for node in row] for row in right] == b;
    return outputs;
}
with entry {
    output = multiply([[1, 2, 3], [4, 5, 6]], [[7, 8], [9, 10], [11, 12]]);
    values = [[node.value for node in row] for row in output];
    assert values == [[58, 64], [139, 154]];
    print(values);
}
