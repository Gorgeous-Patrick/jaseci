"""Architecture-free tensor setup and primitive metadata checks. No op-kind dispatcher."""
import math
from typing import Any
import torch


def metadata(value) -> dict[str, Any]:
    return dict(shape=list(value.shape), dtype=str(value.dtype).removeprefix('torch.'), device=str(value.device))


def tensor_meta(spec):
    return torch.empty(tuple(spec['shape']), device='meta', dtype=getattr(torch, spec['dtype']))


def result(value, device) -> dict[str, Any]:
    spec = metadata(value)
    spec['device'] = device
    return spec


def same_device(*specs) -> str:
    devices = {s['device'] for s in specs}
    if len(devices) != 1:
        raise ValueError(f'device mismatch: {devices}')
    return specs[0]['device']


def floating(spec) -> dict[str, Any]:
    if spec['dtype'] not in ('float32', 'float64'):
        raise ValueError(f'floating primitive requires float32/float64, got {spec}')
    return dict(spec)


def binary(a, b) -> dict[str, Any]:
    device = same_device(a, b)
    floating(a); floating(b)
    if a['dtype'] != b['dtype']:
        raise ValueError('binary dtype mismatch; implicit promotion is outside this example')
    shape = list(torch.broadcast_shapes(tuple(a['shape']), tuple(b['shape'])))
    return dict(shape=shape, dtype=a['dtype'], device=device)


def matmul(a, b) -> dict[str, Any]:
    device = same_device(a, b)
    floating(a); floating(b)
    if a['dtype'] != b['dtype'] or len(a['shape']) < 2 or len(b['shape']) < 2:
        raise ValueError('MatMul requires matching floating dtype and rank >= 2')
    return result(torch.matmul(tensor_meta(a), tensor_meta(b)), device)


def axis(spec, index) -> int:
    rank = len(spec['shape'])
    if not -rank <= index < rank:
        raise ValueError(f'axis {index} outside rank {rank}')
    return index % rank


def mean(spec, index, keepdim) -> dict[str, Any]:
    floating(spec); axis(spec, index)
    return result(tensor_meta(spec).mean(dim=index, keepdim=keepdim), spec['device'])


def reshape(spec, dimensions) -> dict[str, Any]:
    return result(tensor_meta(spec).reshape(tuple(dimensions)), spec['device'])


def transpose(spec, dim0, dim1) -> dict[str, Any]:
    axis(spec, dim0); axis(spec, dim1)
    return result(tensor_meta(spec).transpose(dim0, dim1), spec['device'])


def gather(table, indices, dim) -> dict[str, Any]:
    device = same_device(table, indices)
    axis(table, dim)
    if indices['dtype'] != 'int64' or len(indices['shape']) != 1:
        raise ValueError('Gather indices must be rank-one int64')
    return result(torch.index_select(tensor_meta(table), dim, tensor_meta(indices)), device)


def masked_fill(value, mask) -> dict[str, Any]:
    device = same_device(value, mask)
    floating(value)
    if mask['dtype'] != 'bool':
        raise ValueError('MaskedFill requires bool mask')
    shape = list(torch.broadcast_shapes(tuple(value['shape']), tuple(mask['shape'])))
    if shape != value['shape']:
        raise ValueError('mask would expand value shape')
    return dict(value, device=device)


def full(ref, axes, dtype) -> dict[str, Any]:
    for dim in axes:
        axis(ref, dim)
    shape = [ref['shape'][dim] for dim in axes]
    return result(torch.empty(tuple(shape), device='meta', dtype=getattr(torch, dtype)), ref['device'])


def arange(ref, dim) -> dict[str, Any]:
    axis(ref, dim)
    return dict(shape=[ref['shape'][dim]], dtype='int64', device=ref['device'])


def triu(spec) -> dict[str, Any]:
    if len(spec['shape']) < 2:
        raise ValueError('Triu requires rank >= 2')
    return dict(spec)














def nbytes(spec) -> int:
    return math.prod(spec['shape']) * torch.empty((), dtype=getattr(torch, spec['dtype'])).element_size()


def lifetime_report(order, specs, consumers, persistent, output) -> dict[str, Any]:
    """Derive last uses from real consumer edges and the walker's topological order."""
    indices = {name: i for i, name in enumerate(order)}
    last = {name: max([indices[name], *[indices[c] for c in consumers[name]]]) for name in order}
    last[output] = len(order)  # Return value remains live after execution.
    intervals = {name: dict(definition=indices[name], last_use=last[name],
                           consumer_ports=len(consumers[name]), logical_bytes=nbytes(specs[name]),
                           persistent=name in persistent) for name in order}
    live = set()
    steps = []
    peak_bytes = peak_values = 0
    for i, name in enumerate(order):
        if name not in persistent:
            live.add(name)
        before_bytes = sum(nbytes(specs[n]) for n in live)
        peak_bytes = max(peak_bytes, before_bytes)
        peak_values = max(peak_values, len(live))
        released = sorted(n for n in live if last[n] == i)
        live.difference_update(released)
        steps.append(dict(node=name, release=released, live_after=sorted(live),
                          logical_bytes_after=sum(nbytes(specs[n]) for n in live)))
    return dict(intervals=intervals, steps=steps, peak_logical_bytes=peak_bytes,
                peak_logical_values=peak_values,
                note='Logical tensor values, not allocator memory: aliases counted separately; parameters/constants persistent; diagnostic captures excluded.')
