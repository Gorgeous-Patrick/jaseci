"""Measured lazy Cond correctness, independent direct Torch expectations."""
import argparse
import json
import os
from pathlib import Path
os.environ.setdefault('TORCHINDUCTOR_COMPILE_THREADS', '1')
os.environ.setdefault('MAX_JOBS', '1')
os.environ.setdefault('TORCHINDUCTOR_CACHE_DIR', '/tmp/jac-tensor-runtime-inductor')
import torch
from jaclang.lib.tensor_graph import runtime as r
from validation import reject, preservation


def build(device):
    g = r.TensorGraph(output_name='output')
    g.add(r.Input(name='signal'))
    g.add(r.Input(name='x'))
    g.add(r.Parameter(name='weight', value=torch.tensor([[1., 2.], [3., 4.]], device=device, dtype=torch.float64)))
    g.add(r.Constant(name='zero', value=torch.tensor(0., device=device, dtype=torch.float64)))
    g.add(r.Square(name='condition_dependency'), {'x': 'signal'})
    g.add(r.Greater(name='predicate'), {'a': 'signal', 'b': 'zero'})
    # Include a condition dependency also used by both branches.
    g.add(r.Add(name='condition_value'), {'a': 'condition_dependency', 'b': 'signal'})
    g.rewire('predicate', 'a', 'condition_value')
    g.add(r.MatMul(name='common'), {'a': 'x', 'b': 'weight'})
    g.add(r.Square(name='common_fanout'), {'x': 'common'})
    g.add(r.Add(name='true'), {'a': 'common', 'b': 'condition_value'})
    g.add(r.Subtract(name='false'), {'a': 'common_fanout', 'b': 'condition_value'})
    g.add(r.Cond(name='choose'), {'condition': 'predicate', 'true_result': 'true', 'false_result': 'false'})
    g.add(r.Add(name='output'), {'a': 'choose', 'b': 'zero'})
    return g


def feeds(device, value):
    return dict(signal=torch.tensor(value, device=device, dtype=torch.float64),
                x=torch.tensor([[.1, .2], [.3, .4]], device=device, dtype=torch.float64))


def expectation(g, inputs):
    y = inputs['x'] @ g.ops['weight'].value
    c = inputs['signal'].square() + inputs['signal']
    return y + c if bool((c > 0).item()) else y.square() - c


def check(g, inputs, engines):
    run = g.run(inputs)
    expected = expectation(g, inputs)
    torch.testing.assert_close(run.output, expected, atol=1e-12, rtol=1e-12)
    pred = bool(((inputs['signal'].square() + inputs['signal']) > 0).item())
    selected, excluded = ('true', 'false') if pred else ('false', 'true')
    info = g.plan['conditional']
    expected_trace = info['pre'] + info['true_region' if pred else 'false_region'] + [info['node']] + info['post']
    assert run.trace == expected_trace
    assert all(d['same_object'] for d in run.handle_identity)
    assert all([d['producer'], d['consumer'], d['port']] in g.topology() for d in run.handle_identity)
    assert selected in run.trace and excluded not in run.trace
    assert run.trace.count('common') == run.trace.count('condition_value') == 1
    assert ('common_fanout' not in run.trace) if pred else ('common_fanout' in run.trace)
    assert all(not n.inbox for n in g.ops.values())
    assert all(n.output is None for name, n in g.ops.items() if name != g.output_name)
    engine_errors = {}
    for executable in engines:
        actual = executable(inputs).output
        torch.testing.assert_close(actual, expected, atol=1e-12, rtol=1e-12)
        engine_errors[executable.engine] = float((actual - expected).abs().max().item())
    return dict(predicate=pred, trace=run.trace, output=run.output.detach().cpu().tolist(),
                max_abs_error=float((run.output - expected).abs().max().item()),
                unselected_absent=excluded not in run.trace, engine_max_abs_errors=engine_errors)


def main(root):
    root = Path(root)
    ap = argparse.ArgumentParser(); ap.add_argument('--device', default='cpu'); ap.add_argument('--inductor', action='store_true')
    args = ap.parse_args()
    torch.set_num_threads(1)
    torch.backends.cuda.matmul.allow_tf32 = False
    from torch._inductor import config
    config.compile_threads = 1
    g = build(args.device); inputs = feeds(args.device, .5); plan = g.prepare(inputs)
    fx = g.compile(inputs)
    engines = [fx]
    if args.inductor:
        engines.append(g.compile(inputs, engine='inductor'))
    cases = [check(g, feeds(args.device, value), engines) for value in (.5, -.5, .5, -.25)]
    # Shared pure fanout is computed before selection, exactly once.
    g.rewire('true', 'a', 'common_fanout')
    guards = dict(stale_walker=reject(lambda: g.run(inputs), 'changed'),
                  stale_fx=reject(lambda: fx(inputs), 'changed'))
    if args.inductor:
        guards['stale_inductor'] = reject(lambda: engines[1](inputs), 'changed')
    g.prepare(inputs)
    run = g.run(inputs)
    assert run.trace.count('common_fanout') == 1
    assert run.trace.index('common_fanout') < len(g.plan['conditional']['pre'])
    info = g.plan['conditional']
    assert 'common_fanout' in info['shared_slice']
    for engine in ('fx', 'inductor') if args.inductor else ('fx',):
        torch.testing.assert_close(g.compile(inputs, engine=engine)(inputs).output, run.output)
    # C-only work used by true branch must not be extracted/recomputed there.
    c_only = build(args.device); c_only.rewire('false', 'b', 'zero'); c_only.prepare(inputs)
    ci = c_only.plan['conditional']
    assert 'condition_value' in ci['condition_slice'] and 'condition_value' not in ci['shared_slice']
    assert 'condition_value' not in ci['true_region']
    ce = [c_only.compile(inputs, engine=engine) for engine in (('fx', 'inductor') if args.inductor else ('fx',))]
    for value in (.5, -.5):
        v = feeds(args.device, value); cr = c_only.run(v)
        y = v['x'] @ c_only.ops['weight'].value
        expected = y + v['signal'].square() + v['signal'] if value > 0 else y.square()
        torch.testing.assert_close(cr.output, expected)
        assert cr.trace.count('condition_value') == 1
        for executable in ce:
            torch.testing.assert_close(executable(v).output, expected)
    # Identical result roots: empty exclusive regions; output clone avoids alias.
    g.rewire('choose', 'false_result', 'true'); g.prepare(inputs)
    assert not g.plan['conditional']['true_region'] and not g.plan['conditional']['false_region']
    for value in (.5, -.5):
        v = feeds(args.device, value); run = g.run(v)
        for engine in ('fx', 'inductor') if args.inductor else ('fx',):
            torch.testing.assert_close(g.compile(v, engine=engine)(v).output, run.output)
        assert run.trace.count('true') == 1
    # Compatible values with different producer strides normalize at the join.
    layout = build(args.device)
    layout.add(r.Transpose(name='strided_false', dim0=0, dim1=1), {'x': 'common'})
    layout.rewire('choose', 'false_result', 'strided_false'); layout.prepare(inputs)
    le = [layout.compile(inputs, engine=engine) for engine in (('fx', 'inductor') if args.inductor else ('fx',))]
    for value in (.5, -.5):
        v = feeds(args.device, value); lr = layout.run(v)
        y = v['x'] @ layout.ops['weight'].value
        expected = y + v['signal'].square() + v['signal'] if value > 0 else y.transpose(0, 1)
        torch.testing.assert_close(lr.output, expected)
        assert lr.output.is_contiguous()
        for executable in le:
            result = executable(v).output
            torch.testing.assert_close(result, expected)
            assert result.is_contiguous()
    # Valid metadata but unsafe numeric indexing must NOT run unselected.
    unsafe = build(args.device)
    unsafe.add(r.Constant(name='bad_indices', value=torch.tensor([999, 999], device=args.device)))
    unsafe.add(r.Gather(name='unsafe_gather'), {'table': 'common', 'indices': 'bad_indices'})
    # Remove obsolete false branch to avoid an exclusive region escaping.
    unsafe.rewire('choose', 'false_result', 'unsafe_gather')
    # Existing false is disconnected but pure/unrelated, so executes after Cond.
    unsafe.prepare(inputs)
    ur = unsafe.run(inputs)
    assert 'unsafe_gather' not in ur.trace and torch.isfinite(ur.output).all()
    for engine in ('fx', 'inductor') if args.inductor else ('fx',):
        torch.testing.assert_close(unsafe.compile(inputs, engine=engine)(inputs).output, ur.output)
    selected_unsafe_error = 'not executed on CUDA to avoid poisoning device context'
    if args.device == 'cpu':
        selected_unsafe_error = reject(lambda: unsafe.run(feeds(args.device, -.5)), 'out of range')
        torch.testing.assert_close(unsafe.run(inputs).output, ur.output)
    # Exclusive node-owned weights must be explicit operands, never closures.
    weighted = r.TensorGraph(output_name='choose')
    weighted.add(r.Input(name='signal')); weighted.add(r.Input(name='x'))
    weighted.add(r.Constant(name='zero', value=torch.tensor(0., device=args.device, dtype=torch.float64)))
    weighted.add(r.Greater(name='predicate'), {'a': 'signal', 'b': 'zero'})
    for label, scale in (('true', 2.), ('false', 3.)):
        weighted.add(r.Parameter(name=label + '_weight', value=torch.eye(2, device=args.device, dtype=torch.float64) * scale))
        weighted.add(r.MatMul(name=label), {'a': 'x', 'b': label + '_weight'})
    weighted.add(r.Cond(name='choose'), {'condition': 'predicate', 'true_result': 'true', 'false_result': 'false'})
    weighted.prepare(inputs)
    assert {'true_weight', 'false_weight'} <= set(weighted.plan['conditional']['operands'])
    we = [weighted.compile(inputs, engine=engine) for engine in (('fx', 'inductor') if args.inductor else ('fx',))]
    for value in (.5, -.5):
        v = feeds(args.device, value)
        expected = v['x'] * (2. if value > 0 else 3.)
        torch.testing.assert_close(weighted.run(v).output, expected)
        for executable in we:
            torch.testing.assert_close(executable(v).output, expected)
    weighted.ops['true_weight'].value = weighted.ops['true_weight'].value + .1
    for executable in we:
        torch.testing.assert_close(executable(inputs).output, inputs['x'] @ weighted.ops['true_weight'].value)
    for child in we[0].module.children():
        assert not list(child.buffers()) and not list(child.parameters())
    invalid = guards
    class ImpostorCond(r.Cond):
        pass
    bad = build(args.device); bad.add(ImpostorCond(name='impostor'))
    invalid['exact_identity'] = reject(lambda: bad.prepare(inputs), 'Unsupported exact')
    bad = build(args.device); bad.add(r.Constant(name='bool_vector', value=torch.tensor([True], device=args.device)))
    bad.rewire('choose', 'condition', 'bool_vector')
    invalid['bool_vector'] = reject(lambda: bad.prepare(inputs), 'scalar bool')
    bad = build(args.device); bad.disconnect('false', 'choose', 'false_result')
    invalid['missing_port'] = reject(lambda: bad.prepare(inputs), 'missing input')
    bad = build(args.device); bad.rewire('condition_dependency', 'x', 'output')
    invalid['cycle'] = reject(lambda: bad.prepare(inputs), 'cycle')
    bad = build(args.device); bad.rewire('choose', 'condition', 'x')
    invalid['predicate'] = reject(lambda: bad.prepare(inputs), 'scalar bool')
    bad = build(args.device); bad.rewire('choose', 'false_result', 'signal')
    invalid['outputs'] = reject(lambda: bad.prepare(inputs), 'identical')
    bad = build(args.device); bad.add(r.Cond(name='nested'), {'condition': 'predicate', 'true_result': 'choose', 'false_result': 'output'})
    invalid['nested'] = reject(lambda: bad.prepare(inputs), 'one Cond')
    bad = build(args.device); bad.add(r.Add(name='escape'), {'a': 'true', 'b': 'zero'})
    invalid['escape'] = reject(lambda: bad.prepare(inputs), 'escapes')
    bad = build(args.device); bad.output_name = 'absent'
    invalid['missing_output'] = reject(lambda: bad.prepare(inputs), 'missing selected output')
    bad = build(args.device); bad.prepare(inputs)
    invalid['capture'] = reject(lambda: bad.run(inputs, capture=['true']), 'Capturing exclusive')
    # Metadata inference rejects invalid shapes even in unselected branches.
    bad = build(args.device); bad.add(r.Reshape(name='bad_shape', dimensions=[3]), {'x': 'x'}); bad.rewire('choose', 'false_result', 'bad_shape')
    invalid['invalid_unselected_shape'] = reject(lambda: bad.prepare(inputs), 'metadata inference')
    out = Path(root) / 'results'; out.mkdir(exist_ok=True)
    original = build(args.device); original.prepare(inputs)
    executable = original.compile(inputs)
    suffix = args.device.replace(':', '_')
    executable.export(out / ('cond_' + suffix + '_fx.py'))
    we[0].export(out / ('cond_weighted_' + suffix + '_fx.py'))
    weighted.export_dot(str(out / ('cond_weighted_' + suffix + '.dot')))
    original.export_dot(str(out / ('cond_' + suffix + '.dot')))
    original.export_analysis(str(out / ('cond_' + suffix + '_plan.json')))
    report = dict(status='passed', torch_version=torch.__version__, threads=1, tf32=False,
                  device=args.device, dtype='float64', engines=['walker', 'fx'] + (['inductor'] if args.inductor else []),
                  cases=cases, shared_fanout='passed', same_root='passed', unsafe_unselected_gather='passed',
                  invalid=invalid, branch_layout_normalization='passed', condition_only_branch_dependency='passed', explicit_weight_operands='passed', weight_refresh='passed',
                  selected_unsafe_error=selected_unsafe_error,
                  slices=plan['conditional'], preservation=preservation(root))
    (out / ('cond_' + suffix + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
