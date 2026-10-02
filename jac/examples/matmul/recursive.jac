"""Recursive blocking and seven-product Strassen, with rectangular padding."""

import from common { dimensions, zeros }
import from dense { loop_ijk }

def recursive_accumulate(
    a: list[list[float]],
    b: list[list[float]],
    c: list[list[float]],
    i0: int,
    i1: int,
    j0: int,
    j1: int,
    k0: int,
    k1: int
) {
    m = i1 - i0;
    n = j1 - j0;
    kk = k1 - k0;
    if max(m, n, kk) <= 2 {
        for i in range(i0, i1) {
            for k in range(k0, k1) {
                for j in range(j0, j1) {
                    c[i][j] += a[i][k] * b[k][j];
                }
            }
        }
    } elif m >= n and m >= kk {
        mid = (i0 + i1) // 2;
        recursive_accumulate(a, b, c, i0, mid, j0, j1, k0, k1);
        recursive_accumulate(a, b, c, mid, i1, j0, j1, k0, k1);
    } elif n >= kk {
        mid = (j0 + j1) // 2;
        recursive_accumulate(a, b, c, i0, i1, j0, mid, k0, k1);
        recursive_accumulate(a, b, c, i0, i1, mid, j1, k0, k1);
    } else {
        mid = (k0 + k1) // 2;
        recursive_accumulate(a, b, c, i0, i1, j0, j1, k0, mid);
        recursive_accumulate(a, b, c, i0, i1, j0, j1, mid, k1);
    }
}

def recursive_blocks(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    c = zeros(m, n);
    recursive_accumulate(a, b, c, 0, m, 0, n, 0, kk);
    return c;
}

def combine(
    a: list[list[float]], b: list[list[float]], sign: float = 1.0
) -> list[list[float]] {
    return [[a[i][j] + sign * b[i][j] for j in range(len(a))] for i in range(len(a))];
}

def quadrant(a: list[list[float]], row: int, col: int, size: int) -> list[list[float]] {
    return [a[i][col:col + size] for i in range(row, row + size)];
}

def strassen_square(
    a: list[list[float]], b: list[list[float]], cutoff: int
) -> list[list[float]] {
    n = len(a);
    if n <= cutoff {
        return loop_ijk(a, b);
    }
    h = n // 2;
    a11 = quadrant(a, 0, 0, h);
    a12 = quadrant(a, 0, h, h);
    a21 = quadrant(a, h, 0, h);
    a22 = quadrant(a, h, h, h);
    b11 = quadrant(b, 0, 0, h);
    b12 = quadrant(b, 0, h, h);
    b21 = quadrant(b, h, 0, h);
    b22 = quadrant(b, h, h, h);
    p1 = strassen_square(combine(a11, a22), combine(b11, b22), cutoff);
    p2 = strassen_square(combine(a21, a22), b11, cutoff);
    p3 = strassen_square(a11, combine(b12, b22, -1.0), cutoff);
    p4 = strassen_square(a22, combine(b21, b11, -1.0), cutoff);
    p5 = strassen_square(combine(a11, a12), b22, cutoff);
    p6 = strassen_square(combine(a21, a11, -1.0), combine(b11, b12), cutoff);
    p7 = strassen_square(combine(a12, a22, -1.0), combine(b21, b22), cutoff);
    c11 = combine(combine(combine(p1, p4), p5, -1.0), p7);
    c12 = combine(p3, p5);
    c21 = combine(p2, p4);
    c22 = combine(combine(combine(p1, p2, -1.0), p3), p6);
    c = zeros(n, n);
    for i in range(h) {
        for j in range(h) {
            c[i][j] = c11[i][j];
            c[i][j + h] = c12[i][j];
            c[i + h][j] = c21[i][j];
            c[i + h][j + h] = c22[i][j];
        }
    }
    return c;
}

def strassen(
    a: list[list[float]], b: list[list[float]], cutoff: int = 2
) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    if cutoff < 1 {
        raise ValueError("Cutoff must be positive");
    }
    size = 1;
    while size < max(m, kk, n) {
        size *= 2;
    }
    ap = zeros(size, size);
    bp = zeros(size, size);
    for i in range(m) {
        for k in range(kk) {
            ap[i][k] = a[i][k];
        }
    }
    for k in range(kk) {
        for j in range(n) {
            bp[k][j] = b[k][j];
        }
    }
    cp = strassen_square(ap, bp, cutoff);
    return [row[:n] for row in cp[:m]];
}

# Strassen-Winograd formulas: Kouya, arXiv:1410.1599, equations (5)-(8).
def winograd_square(
    a: list[list[float]], b: list[list[float]], cutoff: int
) -> list[list[float]] {
    n = len(a);
    if n <= cutoff {
        return loop_ijk(a, b);
    }
    h = n // 2;
    a11 = quadrant(a, 0, 0, h);
    a12 = quadrant(a, 0, h, h);
    a21 = quadrant(a, h, 0, h);
    a22 = quadrant(a, h, h, h);
    b11 = quadrant(b, 0, 0, h);
    b12 = quadrant(b, 0, h, h);
    b21 = quadrant(b, h, 0, h);
    b22 = quadrant(b, h, h, h);
    s1 = combine(a21, a22);
    s2 = combine(s1, a11, -1.0);
    s3 = combine(a11, a21, -1.0);
    s4 = combine(a12, s2, -1.0);
    s5 = combine(b12, b11, -1.0);
    s6 = combine(b22, s5, -1.0);
    s7 = combine(b22, b12, -1.0);
    s8 = combine(s6, b21, -1.0);
    m1 = winograd_square(s2, s6, cutoff);
    m2 = winograd_square(a11, b11, cutoff);
    m3 = winograd_square(a12, b21, cutoff);
    m4 = winograd_square(s3, s7, cutoff);
    m5 = winograd_square(s1, s5, cutoff);
    m6 = winograd_square(s4, b22, cutoff);
    m7 = winograd_square(a22, s8, cutoff);
    t1 = combine(m1, m2);
    t2 = combine(t1, m4);
    c11 = combine(m2, m3);
    c12 = combine(combine(t1, m5), m6);
    c21 = combine(t2, m7, -1.0);
    c22 = combine(t2, m5);
    c = zeros(n, n);
    for i in range(h) {
        for j in range(h) {
            c[i][j] = c11[i][j];
            c[i][j + h] = c12[i][j];
            c[i + h][j] = c21[i][j];
            c[i + h][j + h] = c22[i][j];
        }
    }
    return c;
}

def strassen_winograd(
    a: list[list[float]], b: list[list[float]], cutoff: int = 2
) -> list[list[float]] {
    (m, kk, n) = dimensions(a, b);
    if cutoff < 1 {
        raise ValueError("Cutoff must be positive");
    }
    size = 1;
    while size < max(m, kk, n) {
        size *= 2;
    }
    ap = zeros(size, size);
    bp = zeros(size, size);
    for i in range(m) {
        for k in range(kk) {
            ap[i][k] = a[i][k];
        }
    }
    for k in range(kk) {
        for j in range(n) {
            bp[k][j] = b[k][j];
        }
    }
    cp = winograd_square(ap, bp, cutoff);
    return [row[:n] for row in cp[:m]];
}
