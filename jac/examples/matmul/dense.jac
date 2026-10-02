"""Dense CPU implementations, with explicit loop, memory and reduction choices."""

import math;
import from concurrent.futures { ThreadPoolExecutor }
import from array { array }
import from common { dimensions, zeros, transpose }

def loop_ijk(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            for k in range(k_size) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

def loop_ikj(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(m) {
        for k in range(k_size) {
            for j in range(n) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

def loop_jik(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for j in range(n) {
        for i in range(m) {
            for k in range(k_size) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

def loop_jki(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for j in range(n) {
        for k in range(k_size) {
            for i in range(m) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

def loop_kij(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for k in range(k_size) {
        for i in range(m) {
            for j in range(n) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

def loop_kji(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for k in range(k_size) {
        for j in range(n) {
            for i in range(m) {
                c[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return c;
}

def transposed_dot(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    bt = transpose(b);
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            total = 0.0;
            for k in range(k_size) {
                total += a[i][k] * bt[j][k];
            }
            c[i][j] = total;
        }
    }
    return c;
}

def comprehension(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    return [
        [sum(a[i][k] * b[k][j] for k in range(k_size)) for j in range(n)]
        for i in range(m)
    ];
}

def flat_buffers(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    av = array('d', [x for row in a for x in row]);
    bv = array('d', [x for row in b for x in row]);
    cv = array('d', [0.0]) * (m * n);
    for i in range(m) {
        for k in range(k_size) {
            value = av[i * k_size + k];
            for j in range(n) {
                cv[i * n + j] += value * bv[k * n + j];
            }
        }
    }
    return [[cv[i * n + j] for j in range(n)] for i in range(m)];
}

def blocked(
    a: list[list[float]], b: list[list[float]], tile: int = 4
) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    if tile < 1 {
        raise ValueError("Tile size must be positive");
    }
    c = zeros(m, n);
    for i0 in range(0, m, tile) {
        for j0 in range(0, n, tile) {
            for k0 in range(0, k_size, tile) {
                for i in range(i0, min(i0 + tile, m)) {
                    for k in range(k0, min(k0 + tile, k_size)) {
                        value = a[i][k];
                        for j in range(j0, min(j0 + tile, n)) {
                            c[i][j] += value * b[k][j];
                        }
                    }
                }
            }
        }
    }
    return c;
}

def packed_tiles(
    a: list[list[float]], b: list[list[float]], tile: int = 4
) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    if tile < 1 {
        raise ValueError("Tile size must be positive");
    }
    c = zeros(m, n);
    for i0 in range(0, m, tile) {
        for j0 in range(0, n, tile) {
            for k0 in range(0, k_size, tile) {
                im = min(tile, m - i0);
                jn = min(tile, n - j0);
                kk = min(tile, k_size - k0);
                at = [a[i0 + i][k0 + k] for i in range(im) for k in range(kk)];
                bt = [b[k0 + k][j0 + j] for k in range(kk) for j in range(jn)];
                for i in range(im) {
                    for k in range(kk) {
                        value = at[i * kk + k];
                        for j in range(jn) {
                            c[i0 + i][j0 + j] += value * bt[k * jn + j];
                        }
                    }
                }
            }
        }
    }
    return c;
}

def register_2x2(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(0, m, 2) {
        for j in range(0, n, 2) {
            c00 = 0.0;
            c01 = 0.0;
            c10 = 0.0;
            c11 = 0.0;
            for k in range(k_size) {
                a0 = a[i][k];
                b0 = b[k][j];
                a1 = a[i + 1][k] if i + 1 < m else 0.0;
                b1 = b[k][j + 1] if j + 1 < n else 0.0;
                c00 += a0 * b0;
                c01 += a0 * b1;
                c10 += a1 * b0;
                c11 += a1 * b1;
            }
            c[i][j] = c00;
            if j + 1 < n {
                c[i][j + 1] = c01;
            }
            if i + 1 < m {
                c[i + 1][j] = c10;
                if j + 1 < n {
                    c[i + 1][j + 1] = c11;
                }
            }
        }
    }
    return c;
}

def split_k(
    a: list[list[float]], b: list[list[float]], chunk: int = 3
) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    if chunk < 1 {
        raise ValueError("Chunk size must be positive");
    }
    c = zeros(m, n);
    for k0 in range(0, k_size, chunk) {
        partial = zeros(m, n);
        for i in range(m) {
            for j in range(n) {
                for k in range(k0, min(k0 + chunk, k_size)) {
                    partial[i][j] += a[i][k] * b[k][j];
                }
                c[i][j] += partial[i][j];
            }
        }
    }
    return c;
}

def pair_sum(values: list[float], begin: int, end: int) -> float {
    if begin == end {
        return 0.0;
    }
    if end - begin == 1 {
        return values[begin];
    }
    middle = (begin + end) // 2;
    return pair_sum(values, begin, middle) + pair_sum(values, middle, end);
}

def pairwise(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            products = [a[i][k] * b[k][j] for k in range(k_size)];
            c[i][j] = pair_sum(products, 0, k_size);
        }
    }
    return c;
}

def compensated(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            total = 0.0;
            correction = 0.0;
            for k in range(k_size) {
                adjusted = a[i][k] * b[k][j] - correction;
                updated = total + adjusted;
                correction = (updated - total) - adjusted;
                total = updated;
            }
            c[i][j] = total;
        }
    }
    return c;
}

def accurate_sum(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    return [
        [math.fsum(a[i][k] * b[k][j] for k in range(k_size)) for j in range(n)]
        for i in range(m)
    ];
}

def winograd_pairs(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (m, k_size, n) = dimensions(a, b);
    pairs = k_size // 2;
    row_factors = [
        sum(a[i][2 * k] * a[i][2 * k + 1] for k in range(pairs)) for i in range(m)
    ];
    col_factors = [
        sum(b[2 * k][j] * b[2 * k + 1][j] for k in range(pairs)) for j in range(n)
    ];
    c = zeros(m, n);
    for i in range(m) {
        for j in range(n) {
            c[i][j] = -row_factors[i] - col_factors[j];
            for k in range(pairs) {
                c[i][j] += (a[i][2 * k] + b[2 * k + 1][j])
                    * (a[i][2 * k + 1] + b[2 * k][j]);
            }
            if k_size % 2 {
                c[i][j] += a[i][-1] * b[-1][j];
            }
        }
    }
    return c;
}

def row_product(row: list[float], bt: list[list[float]]) -> list[float] {
    return [sum(x * y for (x, y) in zip(row, col)) for col in bt];
}

def threaded_rows(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    dimensions(a, b);
    bt = transpose(b);
    with ThreadPoolExecutor(max_workers=4) as pool {
        futures = [pool.submit(row_product, row, bt) for row in a];
        return [future.result() for future in futures];
    }
}

obj Matrix {
    has data: list[list[float]];

    def __matmul__(other: Matrix) -> Matrix {
        return Matrix(data=loop_ikj(self.data, other.data));
    }
}

def overloaded_operator(
    a: list[list[float]], b: list[list[float]]
) -> list[list[float]] {
    return (Matrix(data=a) @ Matrix(data=b)).data;
}
