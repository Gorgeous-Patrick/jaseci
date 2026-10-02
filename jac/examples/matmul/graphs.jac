"""Seven OSP representations of matmul, executable on CPU Jac.

Only the scalar product-chain pattern matches the current GPU walker subset.
Other patterns intentionally explore richer ordinary Jac semantics.
"""

import from common { dimensions, zeros, transpose }

node Product {
    has left: float,
        right: float;
}

edge NextProduct {}
walker ProductSum {
    has total: float = 0.0;

    can step with Product entry {
        self.total += here.left * here.right;
        visit [->:NextProduct:->];
    }
}

def product_chains(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            terms = [Product(left=a[i][k], right=b[k][j]) for k in range(kk)];
            for k in range(kk - 1) {
                terms[k] +>:NextProduct():+> terms[k + 1];
            }
            w = ProductSum();
            terms[0] spawn w;
            c[i][j] = w.total;
        }
    }
    return c;
}

node Scalar {
    has value: float;
}

edge RowNext {}
edge ColumnNext {}
walker DualDot {
    has rhs: Scalar,
        total: float = 0.0;

    can step with Scalar entry {
        self.total += here.value * self.rhs.value;
        following = [self.rhs->:ColumnNext:->];
        if following {
            self.rhs = following[0];
        }
        visit [->:RowNext:->];
    }
}

def dual_cursors(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    an = [[Scalar(value=a[i][k]) for k in range(kk)] for i in range(m)];
    bn = [[Scalar(value=b[k][j]) for j in range(n)] for k in range(kk)];
    for i in range(m) {
        for k in range(kk - 1) {
            an[i][k] +>:RowNext():+> an[i][k + 1];
        }
    }
    for j in range(n) {
        for k in range(kk - 1) {
            bn[k][j] +>:ColumnNext():+> bn[k + 1][j];
        }
    }
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            w = DualDot(rhs=bn[0][j]);
            an[i][0] spawn w;
            c[i][j] = w.total;
        }
    }
    return c;
}

node DenseRow {
    has values: list[float];
}

walker RowDot {
    has columns: list[list[float]],
        output: list[float] = [];

    can calculate with DenseRow entry {
        self.output = [
            sum(x * y for (x, y) in zip(here.values, col)) for col in self.columns
        ];
    }
}

def row_nodes(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    dimensions(a, b);
    bt = transpose(b);
    c: list[list[float]] = [];
    for row in a {
        w = RowDot(columns=bt);
        DenseRow(values=row) spawn w;
        c.append(w.output);
    }
    return c;
}

node CellTask {
    has row: int,
        col: int;
}

walker CellDot {
    has a: list[list[float]],
        b: list[list[float]],
        total: float = 0.0;

    can calculate with CellTask entry {
        for k in range(len(self.b)) {
            self.total += self.a[here.row][k] * self.b[k][here.col];
        }
    }
}

def output_cell_tasks(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            w = CellDot(a=a, b=b);
            CellTask(row=i, col=j) spawn w;
            c[i][j] = w.total;
        }
    }
    return c;
}

node TileTask {
    has row: int,
        col: int;
}

walker TileDot {
    has a: list[list[float]],
        b: list[list[float]],
        tile: int = 4,
        output: list[list[float]] = [];

    can calculate with TileTask entry {
        im = min(self.tile, len(self.a) - here.row);
        jn = min(self.tile, len(self.b[0]) - here.col);
        self.output = [[0.0 for j in range(jn)] for i in range(im)];
        for k in range(len(self.b)) {
            for i in range(im) {
                value = self.a[here.row + i][k];
                for j in range(jn) {
                    self.output[i][j] += value * self.b[k][here.col + j];
                }
            }
        }
    }
}

def output_tile_tasks(
    a: list[list[float]], b: list[list[float]], tile: int = 4
) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    if tile < 1 {
        raise ValueError("Tile size must be positive");
    }
    c = zeros(m, n);
    for i0 in range(0, m, tile) {
        for j0 in range(0, n, tile) {
            w = TileDot(a=a, b=b, tile=tile);
            TileTask(row=i0, col=j0) spawn w;
            for i in range(len(w.output)) {
                for j in range(len(w.output[i])) {
                    c[i0 + i][j0 + j] = w.output[i][j];
                }
            }
        }
    }
    return c;
}

node LeftValue {
    has value: float;
}

node RightValue {
    has value: float,
        column: int;
}

edge NextLeft {}
edge SameK {}
walker JoinedRow {
    has output: list[float] = [];

    can step with LeftValue entry {
        for other in [->:SameK:->] {
            self.output[other.column] += here.value * other.value;
        }
        visit [->:NextLeft:->];
    }
}

def bipartite_join(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    right = [
        [RightValue(value=b[k][j], column=j) for j in range(n)] for k in range(kk)
    ];
    left = [[LeftValue(value=a[i][k]) for k in range(kk)] for i in range(m)];
    for i in range(m) {
        for k in range(kk) {
            for j in range(n) {
                left[i][k] +>:SameK():+> right[k][j];
            }
            if k + 1 < kk {
                left[i][k] +>:NextLeft():+> left[i][k + 1];
            }
        }
    }
    c: list[list[float]] = [];
    for i in range(m) {
        w = JoinedRow(output=[0.0] * n);
        left[i][0] spawn w;
        c.append(w.output);
    }
    return c;
}

node OutputTask {
    has row: int,
        col: int;
}

node ReductionIndex {
    has index: int;
}

edge Factor {
    has left: float,
        right: float;
}

walker EdgeDot {
    has total: float = 0.0;

    can calculate with OutputTask entry {
        for factor in [edge ->:Factor:->] {
            self.total += factor.left * factor.right;
        }
    }
}

def edge_payloads(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    indices = [ReductionIndex(index=k) for k in range(kk)];
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            output = OutputTask(row=i, col=j);
            for k in range(kk) {
                output +>:Factor(left=a[i][k], right=b[k][j]):+> indices[k];
            }
            w = EdgeDot();
            output spawn w;
            c[i][j] = w.total;
        }
    }
    return c;
}
