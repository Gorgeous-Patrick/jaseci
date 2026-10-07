"""Lazy, architecture-free tensor setup primitives; Jac owns module mathematics."""
from typing import Any


def torch_api() -> Any:
    import torch
    return torch


def device_name(device: str) -> str:
    t = torch_api()
    resolved = t.device(device)
    if resolved.type == 'cuda' and resolved.index is None:
        resolved = t.device('cuda', t.cuda.current_device())
    return str(resolved)


def parameter(value: Any, device: str, dtype: str) -> Any:
    t = torch_api()
    precision = getattr(t, dtype)
    if isinstance(value, t.Tensor):
        return value.detach().to(device=device, dtype=precision).clone()
    return t.tensor(value, device=device, dtype=precision)


def tokens(value: Any, device: str, vocabulary: int) -> Any:
    t = torch_api()
    if isinstance(value, t.Tensor):
        # Metadata only: prevalidated tensor IDs avoid .item()/device-to-host sync.
        if value.ndim != 1 or value.numel() == 0 or value.dtype != t.int64:
            raise ValueError('Expected nonempty one-dimensional int64 token tensor')
        if value.device != t.device(device):
            raise ValueError('Resident token tensors must already be on the model device')
        return value
    if not value or any(type(v) is not int or not 0 <= v < vocabulary for v in value):
        raise ValueError('Token IDs must be nonempty integers in vocabulary')
    return t.tensor(value, device=device, dtype=t.int64)


def argmax(value: Any) -> int:
    # Greedy decoding intentionally reads one ID per step, never per module.
    return int(value.argmax().item())
