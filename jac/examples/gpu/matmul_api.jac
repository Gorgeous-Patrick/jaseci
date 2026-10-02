"""Matrix multiplication through Jac's native PTX walker backend.

This baseline expands the inputs into M*N*K product nodes. It is intended
for correctness and layout experiments, rather than large dense matrices.
"""

import from matmul { ProductTerm, NextTerm, DotProduct }
import from jaclang.runtime.gpu { GpuWalkerRuntime, WalkerBatchResult }

obj MatmulResult {
    has values: list[list[float]], execution: WalkerBatchResult;
}

def matrix_shape(matrix: list[list[float]], name: str) -> tuple[int, int] {
    if not matrix or not matrix[0] {
        raise ValueError(f"{name} must be a nonempty matrix");
    }
    width = len(matrix[0]);
    if any(len(row) != width for row in matrix) {
        raise ValueError(f"{name} must be rectangular");
    }
    return (len(matrix), width);
}

def matmul_graph(
    a: list[list[float]], b: list[list[float]]
) -> tuple[list[DotProduct], list[ProductTerm], int, int] {
    (rows, inner) = matrix_shape(a, "A");
    (other_inner, columns) = matrix_shape(b, "B");
    if inner != other_inner {
        raise ValueError("A's column count must equal B's row count");
    }
    lanes = rows * columns;
    terms = [
        ProductTerm(left=float(a[row][k]), right=float(b[k][col]))
        for k in range(inner)
        for row in range(rows)
        for col in range(columns)
    ];
    # All heads are packed first, then their successors, giving k-major SoA.
    for k in range(inner - 1) {
        for lane in range(lanes) {
            terms[k * lanes + lane] +>:NextTerm():+> terms[(k + 1) * lanes + lane];
        }
    }
    return ([DotProduct() for lane in range(lanes)], terms[:lanes], rows, columns);
}

def gpu_matmul(
    a: list[list[float]], b: list[list[float]], device: int = 0
) -> MatmulResult {
    (walkers, starts, rows, columns) = matmul_graph(a, b);
    with GpuWalkerRuntime(DotProduct, device=device) as gpu {
        execution = gpu.run_walkers(walkers, starts);
        values = [[walkers[row * columns + col].total for col in range(columns)]
            for row in range(rows)];
        return MatmulResult(values=values, execution=execution);
    }
}

def serial_matmul(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    (rows, inner) = matrix_shape(a, "A");
    (other_inner, columns) = matrix_shape(b, "B");
    if inner != other_inner {
        raise ValueError("A's column count must equal B's row count");
    }
    output = [[0.0 for col in range(columns)] for row in range(rows)];
    for row in range(rows) {
        for col in range(columns) {
            for k in range(inner) {
                output[row][col] += float(a[row][k]) * float(b[k][col]);
            }
        }
    }
    return output;
}
