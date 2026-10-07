"""Independent equation differential tests plus executable graph/analysis invariants."""
import argparse
import hashlib
import json
import math
import platform
from pathlib import Path
import torch
from torch.utils._python_dispatch import TorchDispatchMode
import reference

CONFIGS = {'small': dict(dimension=8, heads=2, hidden=16, vocabulary=13),
           'medium': dict(dimension=64, heads=4, hidden=128, vocabulary=127)}


def close(actual, expected, dtype):
    atol, rtol = (2e-11, 2e-10) if dtype == 'float64' else (3e-5, 3e-4)
    torch.testing.assert_close(actual, expected, atol=atol, rtol=rtol, equal_nan=False)
    if expected.dtype == torch.bool:
        return 0.0
    finite = torch.isfinite(expected)
    return float((actual[finite] - expected[finite]).abs().max()) if finite.any() else 0.0


def reject(fn, substring):
    try:
        fn()
    except Exception as exc:
        if substring.lower() not in str(exc).lower():
            raise AssertionError(f'expected {substring!r}, got {exc!r}') from exc
        return str(exc)
    raise AssertionError(f'expected rejection: {substring}')


class ResidentAudit(TorchDispatchMode):
    def __init__(self):
        self.violations = []
        super().__init__()

    def __torch_dispatch__(self, func, types, args=(), kwargs=None):
        kwargs = kwargs or {}
        name = str(func)
        if '_local_scalar_dense' in name:
            self.violations.append(name)
        if '_to_copy' in name and str(kwargs.get('device', '')).startswith('cpu'):
            self.violations.append(name + ': download')
        return func(*args, **kwargs)


def verify_liveness(model, run):
    plan = model.plan
    assert run.trace == plan['order']
    assert sorted(run.deliveries) == sorted(plan['links'])
    assert len(run.handle_identity) == len(plan['links'])
    assert all(edge['same_object'] for edge in run.handle_identity)
    expected = plan['liveness']['steps']
    assert len(run.lifetime_trace) == len(expected)
    for actual, wanted in zip(run.lifetime_trace, expected):
        assert actual['node'] == wanted['node']
        assert actual['release'] == wanted['release'], (actual, wanted)
        assert actual['live_after'] == wanted['live_after'], (actual, wanted)
    for name, op in model.ops.items():
        assert op.inbox == {}
        if name != 'probabilities':
            assert op.output is None
    assert len(set(run.trace)) == len(model.ops)


def compare(model, source, target, dtype, alternate=False):
    expected = reference.forward(model.parameter_snapshot(), source, target, model.dimension, model.heads, alternate)
    run = model.forward(source, target, list(expected))
    errors = {name: close(run.captured[name], tensor, dtype) for name, tensor in expected.items()}
    assert run.probabilities.shape == (target.numel(), model.vocabulary)
    assert torch.isfinite(run.probabilities).all()
    close(run.probabilities.sum(dim=-1), torch.ones(target.numel(), device=target.device, dtype=run.probabilities.dtype), dtype)
    verify_liveness(model, run)
    for name, value in run.captured.items():
        if name != 'dec_attn.masked':
            assert torch.isfinite(value).all(), name
        spec = model.plan['specs'][name]
        assert list(value.shape) == spec['shape'] and str(value.device) == spec['device']
        assert str(value.dtype).removeprefix('torch.') == spec['dtype']
    return run, errors


def case(build, config_name, dtype, device, directory):
    config = CONFIGS[config_name]
    m = build(**config).to(device, dtype)
    source_ids = [3, 4, 5, 2] if config_name == 'small' else list(range(3, 34)) + [2]
    labels = [6, 7, 2] if config_name == 'small' else list(range(40, 63)) + [2]
    target_ids = [1] + labels[:-1]
    source = torch.tensor(source_ids, device=device, dtype=torch.int64)
    target = torch.tensor(target_ids, device=device, dtype=torch.int64)
    plan = m.analyze(source, target)
    run, errors = compare(m, source, target, dtype)
    original = run.probabilities.clone()
    prefix = f'{config_name}_{dtype}_{device.replace(":", "_")}'
    m.export_dot(str(directory / (prefix + '.dot')))
    m.export_analysis(str(directory / (prefix + '_analysis.json')))
    attn = run.captured['dec_attn.probabilities']
    upper = torch.ones(target.numel(), target.numel(), device=device, dtype=torch.bool).triu(1)
    assert torch.count_nonzero(attn[:, upper]) == 0
    # Full expanded norm and both encoder-memory consumers have independent values.
    for name in ('enc_norm1.residual', 'enc_norm1.mean', 'enc_norm1.variance',
                 'cross_attn.k', 'cross_attn.v', 'dec_attn.score', 'dec_attn.masked'):
        assert name in errors
    future = target.clone(); future[-1] = 8
    future_run, _ = compare(m, source, future, dtype)
    close(future_run.probabilities[:-1], original[:-1], dtype)
    close(future_run.captured['dec_attn.probabilities'][:, :-1, :-1], attn[:, :-1, :-1], dtype)
    changed_source = source.clone(); changed_source[0] = 9
    changed_run, _ = compare(m, changed_source, target, dtype)
    influence = float((changed_run.probabilities - original).abs().max())
    assert influence > 1e-7
    # Resident execution cannot download/synchronize per primitive.
    saved_pointers = {n: op.value.data_ptr() for n, op in m.ops.items() if type(op).__name__ == 'Parameter'}
    audit = ResidentAudit()
    original_sync = torch.cuda.synchronize
    def forbidden(*a, **kw):
        raise AssertionError('synchronize inside graph forward')
    torch.cuda.synchronize = forbidden
    try:
        with audit:
            resident = m.forward(source, target)
    finally:
        torch.cuda.synchronize = original_sync
    assert not audit.violations, audit.violations
    assert saved_pointers == {n: op.value.data_ptr() for n, op in m.ops.items() if type(op).__name__ == 'Parameter'}
    verify_liveness(m, resident)
    close(resident.probabilities, original, dtype)
    # Earlier captured tensors survive later inference without mutation.
    close(run.probabilities, original, dtype)
    # Different input lengths invalidate shape-specialized analysis explicitly.
    lengths = []
    for sl, tl in [(2, 1), (1, 5), (5, 2)]:
        s = torch.tensor([3] * sl, device=device, dtype=torch.int64)
        t = torch.tensor([1] + [6] * (tl-1), device=device, dtype=torch.int64)
        reject(lambda: m.forward(s, t), 'input metadata changed')
        m.analyze(s, t)
        _, e = compare(m, s, t, dtype)
        lengths.append(dict(source=sl, target=tl, max_error=max(e.values())))
    m.analyze(source, target)
    # Actual residual edge replacement, old plan must be rejected before numeric work.
    m.rewire('enc_norm1.residual', 'b', 'enc_attn.output')
    invalidation = reject(lambda: m.forward(source, target), 'graph/attributes changed')
    m.analyze(source, target)
    rewired, rewired_errors = compare(m, source, target, dtype, alternate=True)
    delta = float((rewired.probabilities - original).abs().max())
    assert delta > 1e-7
    m.export_dot(str(directory / (prefix + '_rewired.dot')))
    m.export_analysis(str(directory / (prefix + '_rewired_analysis.json')))
    m.rewire('enc_norm1.residual', 'b', 'enc_pos')
    m.analyze(source, target)
    restored, _ = compare(m, source, target, dtype)
    close(restored.probabilities, original, dtype)
    # Node attribute edit changes executable graph; shape-preserving edit too.
    m.ops['dec_attn.probabilities'].axis = -2
    reject(lambda: m.forward(source, target), 'graph/attributes changed')
    m.ops['dec_attn.probabilities'].axis = -1
    m.analyze(source, target)
    # Same-metadata Parameter changes keep analysis valid and affect output.
    mutations = {}
    for name in ['enc_embed.table', 'enc_attn.q.weight', 'dec_attn.k.weight',
                 'cross_attn.v.weight', 'cross_attn.output.bias', 'enc_ffn.up.weight',
                 'dec_ffn.output.weight', 'enc_norm1.gamma', 'dec_norm3.beta', 'projection.weight']:
        op = m.ops[name]; before = op.value.clone()
        # Nonuniform mutation: constant key shifts can cancel in attention softmax.
        perturbation = torch.arange(op.value.numel(), device=device, dtype=op.value.dtype).reshape(op.value.shape)
        op.value = before + .03 * torch.sin(perturbation + 1)
        altered, es = compare(m, source, target, dtype)
        change = float((altered.probabilities - original).abs().max())
        assert change > 1e-8, (name, change)
        mutations[name] = dict(output_delta=change, max_reference_error=max(es.values()))
        op.value = before
    # Both branches of cross-attention actually receive encoder memory by tensor identity.
    links = [tuple(e) for e in m.topology()]
    assert ('enc_norm2', 'cross_attn.k.matmul', 'a') in links
    assert ('enc_norm2', 'cross_attn.v.matmul', 'a') in links
    m.disconnect('enc_norm2', 'cross_attn.k.matmul', 'a')
    missing = reject(lambda: m.analyze(source, target), 'missing input')
    m.wire('enc_norm2', 'cross_attn.k.matmul', 'a')
    m.analyze(source, target)
    # Independent CPU equations using identical parameter values for device differential.
    cpu_params = {n: p.cpu() for n, p in m.parameter_snapshot().items()}
    cpu = reference.forward(cpu_params, source.cpu(), target.cpu(), m.dimension, m.heads)
    final, _ = compare(m, source, target, dtype)
    device_errors = {n: close(final.captured[n].cpu(), value, dtype) for n, value in cpu.items()}
    # Add actual primitive nodes: scaling logits changes structure and inference.
    augmented = build(**config).to(device, dtype)
    ConstantType = type(augmented.ops['embedding_scale'])
    MultiplyType = type(augmented.ops['enc_embed'])
    augmented.add(ConstantType(name='logit_scale', value=torch.tensor(1.2, device=device, dtype=getattr(torch, dtype))))
    augmented.add(MultiplyType(name='scaled_logits'), {'a': 'projection', 'b': 'logit_scale'})
    augmented.rewire('probabilities', 'x', 'scaled_logits')
    augmented.analyze(source, target)
    inserted = augmented.forward(source, target, ['projection'])
    close(inserted.probabilities, torch.softmax(final.captured['projection'] * 1.2, dim=-1), dtype)
    insertion_delta = float((inserted.probabilities - original).abs().max())
    assert insertion_delta > 1e-7
    verify_liveness(augmented, inserted)
    augmented.export_dot(str(directory / (prefix + '_inserted.dot')))
    augmented.export_analysis(str(directory / (prefix + '_inserted_analysis.json')))
    return dict(status='passed', config=config, dtype=dtype, device=device,
                nodes=len(m.ops), edges=len(links), parameters=len(cpu_params),
                checked_intermediates=len(errors), max_reference_error=max(errors.values()),
                max_cpu_device_error=max(device_errors.values()), future_isolation=True,
                encoder_influence=influence, rewired_probability_delta=delta,
                rewired_max_reference_error=max(rewired_errors.values()),
                inserted_primitive_probability_delta=insertion_delta,
                plan_invalidation=invalidation, missing_memory_rejection=missing,
                lengths=lengths, parameter_mutations=mutations, resident_audit=audit.violations,
                liveness=dict(peak_logical_bytes=plan['liveness']['peak_logical_bytes'],
                              peak_logical_values=plan['liveness']['peak_logical_values'],
                              execution_matches_analysis=True))


def bad_graphs(build):
    results = {}
    def fresh():
        return build().to('cpu', 'float64')
    m = fresh(); m.ops['enc_attn.q.weight'].value = torch.zeros((7, 8), dtype=torch.float64)
    results['matmul'] = reject(lambda: m.analyze([3,4], [1,6]), 'metadata inference at enc_attn.q.matmul')
    m = fresh(); m.ops['enc_norm1.gamma'].value = torch.ones(7, dtype=torch.float64)
    results['broadcast'] = reject(lambda: m.analyze([3,4], [1,6]), 'metadata inference at enc_norm1.scaled')
    m = fresh(); m.ops['projection.weight'].value = m.ops['projection.weight'].value.float()
    results['dtype'] = reject(lambda: m.analyze([3,4], [1,6]), 'dtype')
    m = fresh(); m.ops['enc_attn.q.weight'].value = torch.empty((8,8), device='meta', dtype=torch.float64)
    results['device'] = reject(lambda: m.analyze([3,4], [1,6]), 'device mismatch')
    m = fresh(); m.ops['enc_norm1.mean'].axis = 9
    results['axis'] = reject(lambda: m.analyze([3,4], [1,6]), 'axis')
    m = fresh(); m.ops['enc_attn.q.reshape'].dimensions = [-1, 3, 3]
    results['reshape'] = reject(lambda: m.analyze([3,4], [1,6]), 'metadata inference')
    m = fresh(); m.rewire('enc_norm1.residual', 'a', 'enc_norm1')
    results['cycle'] = reject(lambda: m.analyze([3,4], [1,6]), 'cycle')
    m = fresh(); m.wire('enc_pos', 'enc_attn.q.matmul', 'a')
    results['duplicate'] = reject(lambda: m.analyze([3,4], [1,6]), 'duplicate producer')
    m = fresh(); m.wire('enc_pos', 'enc_attn.q.matmul', 'typo')
    results['unknown_port'] = reject(lambda: m.analyze([3,4], [1,6]), 'unknown port')
    m = fresh(); m.rewire('dec_attn.masked', 'mask', 'dec_attn.score')
    results['mask_dtype'] = reject(lambda: m.analyze([3,4], [1,6]), 'bool mask')
    m = fresh(); m.rewire('enc_embed.gather', 'indices', 'embedding_scale')
    results['gather_dtype'] = reject(lambda: m.analyze([3,4], [1,6]), 'Gather indices')
    return results


def main(build, root):
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', default='cpu')
    args = parser.parse_args()
    torch.set_num_threads(1)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    directory = Path(root) / 'results'; directory.mkdir(exist_ok=True)
    report = dict(environment=dict(torch=torch.__version__, python=platform.python_version(),
                                   device=args.device, tf32=False), cases={}, invalid_graphs={})
    with torch.inference_mode():
        for name in CONFIGS:
            for dtype in ('float64', 'float32'):
                print('validate', name, dtype, args.device, flush=True)
                report['cases'][name + '_' + dtype] = case(build, name, dtype, args.device, directory)
        report['invalid_graphs'] = bad_graphs(build)
    report['status'] = 'passed'
    path = directory / ('validation_' + args.device.replace(':','_') + '.json')
    path.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS', path, flush=True)
