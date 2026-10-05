node Scalar { has value: int; }
edge RowNext {}
edge ColumnNext {}
walker Dot {
    cursor a, b;
    has total: int = 0;
    can multiply with (a: Scalar entry, b: Scalar entry) {
        self.total += here[a].value * here[b].value;
        visit[a] [->:RowNext:->];
        visit[b] [->:ColumnNext:->];
    }
}
with entry {
    left = [Scalar(value=v) for v in [1, 2, 3]];
    right = [Scalar(value=v) for v in [4, 5, 6]];
    for i in range(2) {
        left[i] +>:RowNext():+> left[i + 1];
        right[i] +>:ColumnNext():+> right[i + 1];
    }
    result = {"a": left[0], "b": right[0]} spawn Dot();
    assert result.total == 32;
    print(result.total);
}
