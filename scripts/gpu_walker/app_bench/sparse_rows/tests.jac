"""CPU-only checks for sparse row graph construction and arithmetic oracle."""

import from benchmark { build_rows, serial }

test "row sums include empty and irregular rows" {
    (starts, expected, edges) = build_rows(2, 2);
    assert len(starts) == 2;
    assert edges == 2;
    assert expected == [[0, 1], [-21, 3]];
    assert serial(starts, expected) >= 0;
}
