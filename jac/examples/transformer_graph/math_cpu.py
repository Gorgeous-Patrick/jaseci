"""Generic CPU numerical primitives only; no Transformer modules or dispatcher."""
import math
from typing import Any


def random_matrix(rows: int, cols: int, rng: Any) -> list[list[float]]:
    return [[rng.gauss(0, 1 / math.sqrt(rows)) for _ in range(cols)] for _ in range(rows)]


def zeros(rows: int, cols: int) -> list[list[float]]:
    return [[0.0] * cols for _ in range(rows)]


def transpose(x: list[list[float]]) -> list[list[float]]:
    return [list(col) for col in zip(*x, strict=True)]


def matmul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    assert a and b and len(a[0]) == len(b)
    columns = transpose(b)
    return [[sum(u * v for u, v in zip(row, col, strict=True)) for col in columns]
            for row in a]


def affine(x: list[list[float]], w: list[list[float]], bias: list[float]) -> list[list[float]]:
    return [[v + b for v, b in zip(row, bias, strict=True)] for row in matmul(x, w)]


def scale(x: list[list[float]], factor: float) -> list[list[float]]:
    return [[v * factor for v in row] for row in x]


def add(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [[u + v for u, v in zip(arow, brow, strict=True)]
            for arow, brow in zip(a, b, strict=True)]


def relu(x: list[list[float]]) -> list[list[float]]:
    return [[max(0.0, v) for v in row] for row in x]


def softmax(row: list[float]) -> list[float]:
    peak = max(row)
    exps = [math.exp(v - peak) for v in row]
    total = sum(exps)
    return [v / total for v in exps]


def argmax(row: list[float]) -> int:
    return max(range(len(row)), key=row.__getitem__)


def max_error(a: Any, b: Any) -> float:
    if isinstance(a, (list, tuple)):
        assert len(a) == len(b)
        return max((max_error(x, y) for x, y in zip(a, b)), default=0.0)
    return abs(a - b)


def check_probs(probs: list[list[float]], length: int, vocab: int) -> None:
    assert len(probs) == length
    for row in probs:
        assert len(row) == vocab
        assert all(math.isfinite(v) and 0 <= v <= 1 for v in row)
        assert abs(sum(row) - 1) < 1e-12


def check_matrix(x: list[list[float]], rows: int, cols: int) -> None:
    assert len(x) == rows
    assert all(len(row) == cols and all(math.isfinite(v) for v in row) for row in x)
