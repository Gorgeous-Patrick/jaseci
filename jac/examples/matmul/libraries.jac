"""Optional CPU library paths invoked from Jac. All use float64 inputs."""

import importlib;
import importlib.util;
import from common { dimensions }

def numpy_product(
    a: list[list[float]], b: list[list[float]], mode: str
) -> list[list[float]] {
    dimensions(a, b);
    np = importlib.import_module("numpy");
    av = np.asarray(a, dtype=np.float64);
    bv = np.asarray(b, dtype=np.float64);
    if mode == "operator" {
        c = av @ bv;
    } elif mode == "matmul" {
        c = np.matmul(av, bv);
    } elif mode == "dot" {
        c = np.dot(av, bv);
    } elif mode == "einsum" {
        c = np.einsum("ik,kj->ij", av, bv, optimize=True);
    } elif mode == "tensordot" {
        c = np.tensordot(av, bv, axes=([1], [0]));
    } else {
        c = np.sum(
            av.reshape((len(a), len(b), 1)) * bv.reshape((1, len(b), len(b[0]))), axis=1
        );
    }
    return c.tolist();
}

def scipy_blas(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    dimensions(a, b);
    np = importlib.import_module("numpy");
    dgemm = importlib.import_module("scipy.linalg.blas").dgemm;
    return dgemm(
        1.0, np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    ).tolist();
}

def scipy_sparse(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    dimensions(a, b);
    csr_matrix = importlib.import_module("scipy.sparse").csr_matrix;
    return (
        csr_matrix(a, dtype='float64') @ csr_matrix(b, dtype='float64')
    ).toarray().tolist();
}

def availability -> dict[str, bool] {
    return {
        name: importlib.util.find_spec(name) is not None for name in ("numpy", "scipy")
    };
}

def numpy_operator(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    return numpy_product(a, b, "operator");
}

def numpy_matmul(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    return numpy_product(a, b, "matmul");
}

def numpy_dot(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    return numpy_product(a, b, "dot");
}

def numpy_einsum(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    return numpy_product(a, b, "einsum");
}

def numpy_tensordot(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    return numpy_product(a, b, "tensordot");
}

def numpy_broadcast(a: list[list[float]], b: list[list[float]]) -> list[list[float]] {
    return numpy_product(a, b, "broadcast");
}
