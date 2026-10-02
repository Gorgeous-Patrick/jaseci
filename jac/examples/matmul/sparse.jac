"""Sparse CPU products, always returning a dense output matrix."""

import from common { dimensions, zeros }

def csr_dense(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    offsets = [0];
    indices: list[int] = [];
    values: list[float] = [];
    for row in a {
        for k in range(kk) {
            if row[k] != 0.0 {
                indices.append(k);
                values.append(row[k]);
            }
        }
        offsets.append(len(values));
    }
    c = zeros(m, n);
    for i in range(m) {
        for p in range(offsets[i], offsets[i + 1]) {
            k = indices[p];
            for j in range(n) {
                c[i][j] += values[p] * b[k][j];
            }
        }
    }
    return c;
}

def csr_csc_merge(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    ar = [
        [
            (k, a[i][k])
            for k in range(kk)
            if a[i][k] != 0.0
        ] for i in range(m)
    ];
    bc = [
        [
            (k, b[k][j])
            for k in range(kk)
            if b[k][j] != 0.0
        ] for j in range(n)
    ];
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            p = 0;
            q = 0;
            while p < len(ar[i]) and q < len(bc[j]) {
                if ar[i][p][0] == bc[j][q][0] {
                    c[i][j] += ar[i][p][1] * bc[j][q][1];
                    p += 1;
                    q += 1;
                } elif ar[i][p][0] < bc[j][q][0] {
                    p += 1;
                } else {
                    q += 1;
                }
            }
        }
    }
    return c;
}

def coo_scatter(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    entries = [
        (i, k, a[i][k]) for i in range(m)
        for k in range(kk)
        if a[i][k] != 0.0
    ];
    br = [
        [
            (j, b[k][j])
            for j in range(n)
            if b[k][j] != 0.0
        ] for k in range(kk)
    ];
    c = zeros(m, n);
    for (i, k, value) in entries {
        for (j, other) in br[k] {
            c[i][j] += value * other;
        }
    }
    return c;
}
