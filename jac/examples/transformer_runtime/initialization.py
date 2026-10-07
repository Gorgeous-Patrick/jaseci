"""Transformer parameter initialization and token entry preparation, not scheduling."""
import math
import torch

def weight(shape, generator):
    return torch.randn(tuple(shape), generator=generator, dtype=torch.float64) / math.sqrt(shape[0])


def zeros(shape):
    return torch.zeros(tuple(shape), dtype=torch.float64)


def ones(shape):
    return torch.ones(tuple(shape), dtype=torch.float64)


def scalar(value):
    return torch.tensor(value, dtype=torch.float64)


def position_table(length, dimension):
    positions = torch.arange(length, dtype=torch.float64).unsqueeze(1)
    channels = torch.arange(dimension, dtype=torch.float64)
    angles = positions * torch.pow(10000.0, -2.0 * torch.floor(channels / 2) / dimension)
    return torch.where((channels.to(torch.int64) % 2 == 0).unsqueeze(0), angles.sin(), angles.cos())


def tokens(value, device, vocabulary, limit):
    if isinstance(value, torch.Tensor):
        if value.dtype != torch.int64 or value.ndim != 1 or value.numel() == 0:
            raise ValueError('tokens must be nonempty rank-one int64')
        if str(value.device) != device:
            raise ValueError('resident input on wrong device')
        if value.numel() > limit:
            raise ValueError('sequence exceeds positional table capacity')
        # Resident IDs are prevalidated by the caller; no device scalar read here.
        return value
    if not value or len(value) > limit or any(type(v) is not int or not 0 <= v < vocabulary for v in value):
        raise ValueError('invalid token IDs/length')
    return torch.tensor(value, device=device, dtype=torch.int64)
