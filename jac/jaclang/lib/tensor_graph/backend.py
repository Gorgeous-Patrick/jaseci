"""Library/runtime FX lowering. This does not modify or integrate the Jac compiler.

Dispatch is by exact canonical Jac class identity, never a user kind string or
class-name match. Shapes and operand ports come from validated real graph edges.
"""
from dataclasses import dataclass
import operator
from typing import Any
import torch
from . import numerics


def operation_types():
    from . import runtime as r
    return (r.Input, r.Parameter, r.Constant, r.Gather, r.MatMul, r.Add, r.Multiply,
            r.Subtract, r.Square, r.Rsqrt, r.ReduceMean, r.Reshape, r.Transpose,
            r.MaskedFill, r.Softmax, r.ReLU, r.Contiguous, r.Arange, r.Full, r.Triu, r.Greater, r.Cond)


def validate_types(model) -> None:
    supported = operation_types()
    for node in model.ops.values():
        if type(node) not in supported:
            raise TypeError(f'Unsupported exact primitive type: {type(node)!r}')
        if any(method in vars(node) for method in ('evaluate', 'infer', 'ports', 'attributes')):
            raise TypeError('Instance overrides of primitive semantics are unsupported')


def check_feeds(model, values) -> None:
    from .runtime import Input
    expected = {name for name, node in model.ops.items() if type(node) is Input}
    if set(values) != expected:
        raise ValueError(f'Input feeds must match exactly: expected {sorted(expected)}, got {sorted(values)}')
    if any(not isinstance(value, torch.Tensor) for value in values.values()):
        raise TypeError('Input feeds must be tensors')


def schema(node) -> dict[str, Any]:
    """Inspectable semantic declaration; not an execution dispatcher."""
    from . import runtime as r
    semantics = {
        r.Input: 'tensor input', r.Parameter: 'persistent node-owned tensor parameter',
        r.Constant: 'persistent non-trainable tensor', r.Gather: 'torch.index_select(table, axis, indices)',
        r.MatMul: 'torch.matmul(a, b), rank >= 2', r.Add: 'torch.add(a, b)',
        r.Multiply: 'torch.mul(a, b)', r.Subtract: 'torch.sub(a, b)',
        r.Square: 'torch.square(x)', r.Rsqrt: 'torch.rsqrt(x)',
        r.ReduceMean: 'x.mean(dim=axis, keepdim=keepdim)', r.Reshape: 'x.reshape(dimensions)',
        r.Transpose: 'x.transpose(dim0, dim1)', r.MaskedFill: 'x.masked_fill(mask, fill)',
        r.Softmax: 'torch.softmax(x, dim=axis)', r.ReLU: 'torch.relu(x)',
        r.Contiguous: 'x.contiguous()', r.Arange: 'arange(ref.shape[axis], int64, ref.device)',
        r.Full: 'full(tuple(ref.shape[i] for i in axes), fill, dtype, ref.device)',
        r.Triu: 'x.triu(diagonal)', r.Greater: 'torch.gt(a, b)',
        r.Cond: 'lazy scalar-bool selection; precompute shared pure dependencies; contiguous clone of selected result',
    }
    cls = type(node)
    if cls not in semantics:
        raise TypeError(f'Unsupported exact primitive type: {cls}')
    return dict(qualified_type=cls.__module__ + '.' + cls.__name__, ports=node.ports(),
                attributes=node.attributes(), semantics=semantics[cls], version=1)


def lower_graph(model, capture=()):
    from . import runtime as r
    validate_types(model)
    if model.plan is None or model.plan['fingerprint'] != model.fingerprint():
        raise ValueError('Fresh prepare() required before FX lowering')
    capture = tuple(capture)
    if len(set(capture)) != len(capture) or any(name not in model.ops for name in capture):
        raise ValueError('Unknown or duplicate FX capture names')
    fx = torch.fx.Graph()
    module = torch.nn.Module()
    converted = {}
    input_names, bindings = [], {}
    # Each key is an exact canonical class. No architecture/module lowering here.
    binaries = {r.MatMul: torch.matmul, r.Add: torch.add, r.Multiply: torch.mul, r.Subtract: torch.sub, r.Greater: torch.gt}
    unaries = {r.Square: torch.square, r.Rsqrt: torch.rsqrt, r.ReLU: torch.relu}
    def emit(fx, module, converted, name, index):
        node = model.ops[name]
        cls = type(node)
        ports = {port: converted[src] for port, src in model.plan['sources'][name].items()}
        if cls is r.Input:
            # Valid Python identifiers are generated independently of Jac names.
            value = fx.placeholder('input_' + str(len(input_names)))
            input_names.append(name)
        elif cls in (r.Parameter, r.Constant):
            slot = 'tensor_' + str(index)
            # Buffers alias Jac-owned tensors. Parameter vs Constant is explicit metadata.
            module.register_buffer(slot, node.value, persistent=True)
            bindings[name] = slot
            value = fx.get_attr(slot)
        elif cls in binaries:
            value = fx.call_function(binaries[cls], (ports['a'], ports['b']))
        elif cls in unaries:
            value = fx.call_function(unaries[cls], (ports['x'],))
        elif cls is r.Gather:
            value = fx.call_function(torch.index_select, (ports['table'], node.axis, ports['indices']))
        elif cls is r.Softmax:
            value = fx.call_function(torch.softmax, (ports['x'],), {'dim': node.axis})
        elif cls is r.ReduceMean:
            value = fx.call_method('mean', (ports['x'],), {'dim': node.axis, 'keepdim': node.keepdim})
        elif cls is r.Reshape:
            value = fx.call_method('reshape', (ports['x'], tuple(node.dimensions)))
        elif cls is r.Transpose:
            value = fx.call_method('transpose', (ports['x'], node.dim0, node.dim1))
        elif cls is r.Contiguous:
            value = fx.call_method('contiguous', (ports['x'],))
        elif cls is r.MaskedFill:
            value = fx.call_method('masked_fill', (ports['x'], ports['mask'], node.fill))
        elif cls is r.Triu:
            value = fx.call_method('triu', (ports['x'], node.diagonal))
        elif cls in (r.Arange, r.Full):
            ref = ports['ref']
            shape = fx.call_function(getattr, (ref, 'shape'))
            device = fx.call_function(getattr, (ref, 'device'))
            if cls is r.Arange:
                length = fx.call_function(operator.getitem, (shape, node.axis))
                value = fx.call_function(torch.arange, (length,), {'dtype': torch.int64, 'device': device})
            else:
                dimensions = tuple(fx.call_function(operator.getitem, (shape, axis)) for axis in node.axes)
                value = fx.call_function(torch.full, (dimensions, node.fill),
                                         {'dtype': getattr(torch, node.dtype), 'device': device})
        else:
            raise TypeError(f'No lowering for exact type {cls!r}')
        value.meta['jac_name'] = name
        value.meta['jac_semantic'] = schema(node)
        value.meta['tensor_spec'] = dict(model.plan['specs'][name])
        converted[name] = value
    info = model.plan.get('conditional')
    if info is not None and set(capture).intersection(info['true_region'] + info['false_region']):
        raise ValueError('Capturing exclusive branch nodes is unsupported')
    if info is None:
        for index, name in enumerate(model.plan['order']):
            emit(fx, module, converted, name, index)
    else:
        for name in info['pre']:
            emit(fx, module, converted, name, model.plan['order'].index(name))
        branches = []
        for label in ('true', 'false'):
            branch_graph = torch.fx.Graph()
            branch_module = torch.nn.Module()
            branch_values = {name: branch_graph.placeholder('operand_' + str(i))
                             for i, name in enumerate(info['operands'])}
            for name in info[label + '_region']:
                emit(branch_graph, branch_module, branch_values, name, model.plan['order'].index(name))
            # torch.cond forbids output aliasing inputs; normalize both branches.
            contiguous = branch_graph.call_method('contiguous', (branch_values[info[label + '_root']],))
            result = branch_graph.call_method('clone', (contiguous,))
            branch_graph.output((result,))
            branch_graph.lint()
            gm = torch.fx.GraphModule(branch_module, branch_graph, 'JacCond' + label.title())
            slot = 'cond_' + label
            module.add_module(slot, gm)
            branches.append(fx.get_attr(slot))
        result = fx.call_function(torch.ops.higher_order.cond,
                                 (converted[info['condition_root']], branches[0], branches[1],
                                  tuple(converted[n] for n in info['operands'])))
        value = fx.call_function(operator.getitem, (result, 0))
        node = model.ops[info['node']]
        value.meta.update(jac_name=node.name, jac_semantic=schema(node),
                          tensor_spec=dict(model.plan['specs'][node.name]))
        converted[node.name] = value
        for name in info['post']:
            emit(fx, module, converted, name, model.plan['order'].index(name))
    fx.output((converted[model.output_name], tuple(converted[name] for name in capture)))
    fx.lint()
    graph_module = torch.fx.GraphModule(module, fx, 'JacTensorGraph')
    return graph_module, tuple(input_names), bindings


@dataclass
class Result:
    output: Any
    captured: dict[str, Any]


class Executable:
    """Guarded graph snapshot; parameter values refresh from the owning Jac nodes."""
    def __init__(self, model, engine, capture):
        if engine not in ('fx', 'inductor'):
            raise ValueError('engine must be fx or inductor')
        self.model, self.engine, self.capture = model, engine, tuple(capture)
        self.fingerprint = model.plan['fingerprint']
        self.input_specs = dict(model.plan['input_specs'])
        self.module, self.input_names, self.bindings = lower_graph(model, capture)
        self.core = self.module
        if engine == 'inductor':
            self.core = torch.compile(self.module, backend='inductor', fullgraph=True, dynamic=False,
                                      options={'triton.cudagraphs': False})

    def __call__(self, values):
        check_feeds(self.model, values)
        if self.model.fingerprint() != self.fingerprint:
            raise ValueError('Graph changed: lower/compile again')
        if {name: numerics.metadata(value) for name, value in values.items()} != self.input_specs:
            raise ValueError('Input metadata changed: lower/compile again')
        # Same-metadata value replacement is legal; do not retain a stale weight snapshot.
        for name, slot in self.bindings.items():
            self.module._buffers[slot] = self.model.ops[name].value
        with torch.inference_mode():
            output, captures = self.core(*(values[name] for name in self.input_names))
        return Result(output, dict(zip(self.capture, captures)))

    def export(self, filename):
        # Generated FX source is inspectable and derived from the actual graph.
        from pathlib import Path
        header = '"""Generated FX forward for inspection; tensors are bound by Executable."""\nimport torch\nfrom math import inf\n\n'
        source = header + self.module.code.lstrip()
        for name, child in self.module.named_children():
            if isinstance(child, torch.fx.GraphModule):
                source += '\n# Extracted branch module: ' + name + '\n' + child.code.lstrip()
        Path(filename).write_text('\n'.join(line.rstrip() for line in source.splitlines()).rstrip() + '\n')


def compile_graph(model, engine='fx', capture=()) -> Any:
    return Executable(model, engine, capture)
