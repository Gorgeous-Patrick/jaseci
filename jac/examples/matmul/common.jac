"""Shared shape validation and allocation for real-valued CPU matmul examples."""

def dimensions(a: list[list[float]], b: list[list[float]]) -> tuple[int, int, int] {
    if not a or not b or not a[0] or not b[0] {
        raise ValueError("Matrices must be nonempty");
    }
    k = len(a[0]);
    n = len(b[0]);
    if any(len(row) != k for row in a) or any(len(row) != n for row in b) {
        raise ValueError("Matrices must be rectangular");
    }
    if k != len(b) {
        raise ValueError("Inner dimensions must match");
    }
    return (len(a), k, n);
}

def zeros(m: int, n: int) -> list[list[float]] {
    return [[0.0 for j in range(n)] for i in range(m)];
}

def transpose(b: list[list[float]]) -> list[list[float]] {
    return [[b[k][j] for k in range(len(b))] for j in range(len(b[0]))];
}
