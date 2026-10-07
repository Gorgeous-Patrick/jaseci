"""Library reuse, full Transformer, dependency/lifetime, FX and Inductor tests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform

os.environ.setdefault('TORCHINDUCTOR_COMPILE_THREADS', '1')
os.environ.setdefault('MAX_JOBS', '1')
os.environ.setdefault('TORCHINDUCTOR_CACHE_DIR', '/tmp/jac-tensor-runtime-inductor')

import torch
from torch.utils._python_dispatch import TorchDispatchMode
from jaclang.lib.tensor_graph import runtime as rt
from jaclang.lib.tensor_graph import backend
import reference

CONFIGS = {'small': dict(dimension=8, heads=2, hidden=16, vocabulary=13),
           'medium': dict(dimension=64, heads=4, hidden=128, vocabulary=127)}


def close(actual, expected, dtype):
    atol, rtol = (2e-11, 2e-10) if dtype == 'float64' else (3e-5, 3e-4)
    torch.testing.assert_close(actual, expected, atol=atol, rtol=rtol)
    if actual.dtype == torch.bool:
        return 0.0
    finite = torch.isfinite(expected)
    return float((actual[finite] - expected[finite]).abs().max()) if finite.any() else 0.0


def reject(fn, substring):
    try:
        fn()
    except Exception as exc:
        if substring.lower() not in str(exc).lower():
            raise AssertionError(f'expected {substring!r}, got {exc!r}') from exc
        return str(exc)[:400]
    raise AssertionError('expected rejection: ' + substring)


class Audit(TorchDispatchMode):
    def __init__(self):
        super().__init__(); self.violations = []
    def __torch_dispatch__(self, func, types, args=(), kwargs=None):
        kwargs = kwargs or {}
        if '_local_scalar_dense' in str(func):
            self.violations.append(str(func))
        if '_to_copy' in str(func) and str(kwargs.get('device', '')).startswith('cpu'):
            self.violations.append('CPU download')
        return func(*args, **kwargs)


def check_lifetime(graph, result):
    assert result.trace == graph.plan['order']
    assert sorted(result.deliveries) == sorted(graph.plan['links'])
    assert all(row['same_object'] for row in result.handle_identity)
    assert len(result.handle_identity) == len(graph.plan['links'])
    for actual, wanted in zip(result.lifetime_trace, graph.plan['liveness']['steps']):
        assert all(actual[k] == wanted[k] for k in ('node', 'release', 'live_after'))
    assert len(result.lifetime_trace) == len(graph.ops)
    for name, node in graph.ops.items():
        assert not node.inbox
        if name != graph.output_name:
            assert node.output is None


def equations(graph, feeds, config, alternate=False):
    return reference.forward(graph.parameter_snapshot(), feeds['source'], feeds['target'],
                             config['dimension'], config['heads'], alternate)


def walker_check(graph, feeds, config, dtype, alternate=False):
    expected = equations(graph, feeds, config, alternate)
    result = graph.run(feeds, list(expected))
    errors = {name: close(result.captured[name], value, dtype) for name, value in expected.items()}
    assert result.output.shape == (feeds['target'].numel(), config['vocabulary'])
    close(result.output.sum(-1), torch.ones_like(result.output.sum(-1)), dtype)
    for name, value in result.captured.items():
        if name != 'dec_attn.masked':
            assert torch.isfinite(value).all(), name
    check_lifetime(graph, result)
    return result, expected, max(errors.values())


def lowered_check(executable, feeds, expected, dtype):
    result = executable(feeds)
    maximum = close(result.output, expected['probabilities'], dtype)
    for name, value in expected.items():
        maximum = max(maximum, close(result.captured[name], value, dtype))
    return result, maximum


def compile_check(graph, feeds, expected, dtype, enabled):
    if not enabled:
        return dict(status='not_requested')
    try:
        executable = graph.compile(feeds, 'inductor', list(expected))
        result, error = lowered_check(executable, feeds, expected, dtype)
        repeat, repeated_error = lowered_check(executable, feeds, expected, dtype)
        close(result.output, repeat.output, dtype)
    except AssertionError:
        raise
    except Exception as exc:
        return dict(status='unsupported_or_failed', error=repr(exc)[:2000])
    return dict(status='passed', backend='inductor', fullgraph=True, dynamic=False,
                cudagraphs=False, max_intermediate_error=max(error, repeated_error))


def transformer_case(build, label, dtype, device, directory, compile_enabled):
    config = CONFIGS[label]
    graph = build(**config).to(device, dtype)
    source = [3,4,5,2] if label == 'small' else list(range(3,34))+[2]
    labels = [6,7,2] if label == 'small' else list(range(40,63))+[2]
    feeds = dict(source=torch.tensor(source, device=device), target=torch.tensor([1]+labels[:-1], device=device))
    result, expected, reference_error = walker_check(graph, feeds, config, dtype)
    original = result.output.clone()
    old_plan = graph.plan
    assert len(graph.ops)==200 and len(graph.topology())==224
    assert len(graph.parameter_snapshot())==46 and len(expected)==137
    fx = graph.compile(feeds, 'fx', list(expected))
    lowered, fx_error = lowered_check(fx, feeds, expected, dtype)
    close(lowered.output, result.output, dtype)
    # Every library primitive is represented by one semantically labelled FX value.
    represented = [n for n in fx.module.graph.nodes if 'jac_name' in n.meta]
    assert len(represented)==len(graph.ops)
    assert {n.meta['jac_name'] for n in represented}==set(graph.ops)
    assert all(n.meta['jac_semantic']['qualified_type'].startswith('jaclang.lib.tensor_graph.runtime.') for n in represented)
    prefix = label+'_'+dtype+'_'+device.replace(':','_')
    if label=='small' and dtype=='float64':
        graph.export_dot(str(directory/(prefix+'.dot')))
        fx.export(directory/(prefix+'_fx.py'))
        (directory/(prefix+'_plan.json')).write_text(json.dumps({
            'nodes':len(graph.ops), 'edges':graph.topology(), 'order':graph.plan['order'],
            'liveness':graph.plan['liveness'], 'schemas':{name:backend.schema(n) for name,n in graph.ops.items()}},indent=2)+'\n')
    compiled = compile_check(graph, feeds, expected, dtype, compile_enabled)
    # Different values with identical metadata: reused graph and FX executable.
    future = dict(feeds, target=feeds['target'].clone()); future['target'][-1]=8
    changed, future_expected, _ = walker_check(graph, future, config, dtype)
    _, future_fx_error = lowered_check(fx, future, future_expected, dtype)
    close(changed.output[:-1], original[:-1], dtype)
    mask = torch.ones(len(labels),len(labels),device=device,dtype=torch.bool).triu(1)
    assert torch.count_nonzero(result.captured['dec_attn.probabilities'][:,mask])==0
    encoder = dict(feeds, source=feeds['source'].clone()); encoder['source'][0]=9
    memory_run, memory_expected, _ = walker_check(graph, encoder, config, dtype)
    lowered_check(fx, encoder, memory_expected, dtype)
    influence=float((memory_run.output-original).abs().max()); assert influence>1e-7
    # Forward region audit excludes validation, uploads, compilation and scalar assertions.
    audit=Audit(); saved_sync=torch.cuda.synchronize
    def forbidden(*args,**kwargs): raise AssertionError('synchronize inside forward')
    torch.cuda.synchronize=forbidden
    try:
        with audit:
            audited=graph.run(feeds)
            audited_fx=fx(feeds)
    finally:
        torch.cuda.synchronize=saved_sync
    assert not audit.violations
    close(audited.output, original, dtype); close(audited_fx.output, original, dtype)
    close(result.output, original, dtype)  # Earlier result survives later runs.
    lengths=[]
    for sl,tl in [(2,1),(1,5),(5,2)]:
        values={'source':torch.tensor([3]*sl,device=device),'target':torch.tensor([1]+[6]*(tl-1),device=device)}
        reject(lambda:graph.run(values),'input metadata changed')
        reject(lambda:fx(values),'input metadata changed')
        graph.prepare(values)
        r,e,err=walker_check(graph,values,config,dtype)
        fresh_fx=graph.compile(values,'fx',list(e)); lowered_check(fresh_fx,values,e,dtype)
        lengths.append(dict(source=sl,target=tl,max_error=err))
    graph.prepare(feeds)
    # A real residual edge edit invalidates both walker plan and old FX executable.
    graph.rewire('enc_norm1.residual','b','enc_attn.output')
    reject(lambda:graph.run(feeds),'graph/attributes changed')
    reject(lambda:fx(feeds),'graph changed')
    graph.prepare(feeds)
    alternate,alt_expected,alternate_error=walker_check(graph,feeds,config,dtype,True)
    delta=float((alternate.output-original).abs().max()); assert delta>1e-7
    alt_fx=graph.compile(feeds,'fx',list(alt_expected))
    _,alt_fx_error=lowered_check(alt_fx,feeds,alt_expected,dtype)
    if label=='small' and dtype=='float64':
        graph.export_dot(str(directory/(prefix+'_rewired.dot'))); alt_fx.export(directory/(prefix+'_rewired_fx.py'))
    alternate_compiled=compile_check(graph,feeds,alt_expected,dtype,compile_enabled and label=='small' and dtype=='float64')
    graph.rewire('enc_norm1.residual','b','enc_pos'); graph.prepare(feeds)
    restored,_,_=walker_check(graph,feeds,config,dtype); close(restored.output,original,dtype)
    # An FX callable follows current Parameter.value even after same-metadata replacement.
    mutations={}
    for name in ['enc_embed.table','enc_attn.q.weight','dec_attn.k.weight','cross_attn.v.weight',
                 'cross_attn.output.bias','enc_ffn.up.weight','dec_ffn.output.weight',
                 'enc_norm1.gamma','dec_norm3.beta','projection.weight']:
        node=graph.ops[name]; before=node.value.clone()
        indices=torch.arange(before.numel(),device=device,dtype=before.dtype).reshape(before.shape)
        node.value=before+0.03*torch.sin(indices+1)
        updated,update_expected,err=walker_check(graph,feeds,config,dtype)
        _,weight_fx_error=lowered_check(fx,feeds,update_expected,dtype)
        change=float((updated.output-original).abs().max()); assert change>1e-8
        mutations[name]=dict(output_delta=change,max_reference_error=err,max_fx_error=weight_fx_error)
        node.value=before
    graph.disconnect('enc_norm2','cross_attn.k.matmul','a')
    missing=reject(lambda:graph.prepare(feeds),'missing input')
    reject(lambda:graph.compile(feeds),'missing input')
    graph.wire('enc_norm2','cross_attn.k.matmul','a'); graph.prepare(feeds)
    # Actual primitive insertion, no model/runtime flow changes.
    graph.add(rt.Constant(name='logit_scale',value=torch.tensor(1.2,device=device,dtype=getattr(torch,dtype))))
    graph.add(rt.Multiply(name='scaled_logits'),{'a':'projection','b':'logit_scale'})
    graph.rewire('probabilities','x','scaled_logits'); graph.prepare(feeds)
    inserted=graph.run(feeds,['projection']); check_lifetime(graph,inserted)
    insertion_expected=torch.softmax(expected['projection']*1.2,dim=-1)
    close(inserted.output,insertion_expected,dtype)
    inserted_fx=graph.compile(feeds,'fx',['projection'])
    close(inserted_fx(feeds).output,insertion_expected,dtype)
    assert len(graph.ops)==202 and len(graph.topology())==226
    # Compare GPU against independent CPU equations on identical weights.
    cpu_params={name:p.cpu() for name,p in graph.parameter_snapshot().items()}
    cpu=reference.forward(cpu_params,feeds['source'].cpu(),feeds['target'].cpu(),config['dimension'],config['heads'])
    device_error=max(close(expected[name].cpu(),cpu[name],dtype) for name in expected)
    return dict(status='passed',nodes=200,edges=224,parameters=46,checked_intermediates=137,
                max_reference_error=reference_error,max_fx_intermediate_error=fx_error,
                max_cpu_device_error=device_error,compiled=compiled,rewired_compiled=alternate_compiled,
                causal_future_isolation=True,encoder_influence=influence,
                rewired_probability_delta=delta,rewired_reference_error=alternate_error,rewired_fx_error=alt_fx_error,
                inserted_nodes=202,inserted_edges=226,resident_forward_audit=audit.violations,
                lengths=lengths,mutations=mutations,missing_input_rejection=missing,
                liveness_matches_execution=True,logical_peak_bytes=old_plan['liveness']['peak_logical_bytes'])


def generic_reuse(device):
    """A non-Transformer graph with different feed/output names, same public Compute."""
    graph=rt.TensorGraph(output_name='result')
    graph.add(rt.Input(name='left')); graph.add(rt.Input(name='right'))
    graph.add(rt.Parameter(name='offset',value=torch.tensor([1.,2.],device=device,dtype=torch.float64)))
    graph.add(rt.MatMul(name='product'),{'a':'left','b':'right'})
    graph.add(rt.Add(name='result'),{'a':'product','b':'offset'})
    values={'left':torch.tensor([[1.,2.],[3.,4.]],device=device,dtype=torch.float64),
            'right':torch.eye(2,device=device,dtype=torch.float64)}
    expected=values['left']+graph.ops['offset'].value
    run=graph.run(values); close(run.output,expected,'float64'); check_lifetime(graph,run)
    fx=graph.compile(values); close(fx(values).output,expected,'float64')
    graph.ops['offset'].value=graph.ops['offset'].value+3
    close(fx(values).output,expected+3,'float64')
    return dict(status='passed',nodes=5,edges=4,input_names=list(values),output='result',fx_parity=True)


def invalid_graphs(build):
    def fresh(): return build().to('cpu','float64')
    values={'source':torch.tensor([3,4]),'target':torch.tensor([1,6])}
    results={}
    g=fresh(); g.ops['enc_attn.q.weight'].value=torch.zeros((7,8),dtype=torch.float64)
    results['matmul']=reject(lambda:g.prepare(values),'metadata inference')
    g=fresh(); g.ops['enc_norm1.gamma'].value=torch.ones(7,dtype=torch.float64)
    results['broadcast']=reject(lambda:g.prepare(values),'metadata inference')
    g=fresh(); g.ops['projection.weight'].value=g.ops['projection.weight'].value.float()
    results['dtype']=reject(lambda:g.prepare(values),'dtype')
    g=fresh(); g.ops['enc_attn.q.weight'].value=torch.empty((8,8),device='meta',dtype=torch.float64)
    results['device']=reject(lambda:g.prepare(values),'device mismatch')
    g=fresh(); g.ops['enc_norm1.mean'].axis=9
    results['axis']=reject(lambda:g.prepare(values),'axis')
    g=fresh(); g.ops['enc_attn.q.reshape'].dimensions=[-1,3,3]
    results['reshape']=reject(lambda:g.prepare(values),'metadata inference')
    g=fresh(); g.rewire('enc_norm1.residual','a','enc_norm1')
    results['cycle']=reject(lambda:g.prepare(values),'cycle')
    g=fresh(); g.wire('enc_pos','enc_attn.q.matmul','a')
    results['duplicate']=reject(lambda:g.prepare(values),'duplicate producer')
    g=fresh(); g.wire('enc_pos','enc_attn.q.matmul','typo')
    results['unknown_port']=reject(lambda:g.prepare(values),'unknown port')
    g=fresh(); g.disconnect('enc_norm2','cross_attn.k.matmul','a')
    results['missing_port']=reject(lambda:g.prepare(values),'missing input')
    g=fresh(); g.rewire('dec_attn.masked','mask','dec_attn.score')
    results['mask_dtype']=reject(lambda:g.prepare(values),'bool mask')
    g=fresh(); g.rewire('enc_embed.gather','indices','embedding_scale')
    results['gather_dtype']=reject(lambda:g.prepare(values),'Gather indices')
    g=fresh(); results['missing_feed']=reject(lambda:g.prepare({'source':values['source']}),'feeds must match')
    results['extra_feed']=reject(lambda:g.prepare(dict(values,extra=values['source'])),'feeds must match')
    results['not_tensor']=reject(lambda:g.prepare(dict(values,source=[3,4])),'must be tensors')
    g=fresh(); g.output_name='absent'
    results['missing_output']=reject(lambda:g.prepare(values),'missing selected output')
    g=fresh(); g.prepare(values); fx=g.compile(values)
    g.ops['dec_attn.probabilities'].axis=-2
    results['attribute_plan_invalidation']=reject(lambda:g.run(values),'graph/attributes changed')
    results['attribute_fx_invalidation']=reject(lambda:fx(values),'graph changed')
    # Same name/base class is insufficient; exact registered type identity is required.
    class Add(rt.Add): pass
    g=fresh(); g.add(Add(name='spoof'),{'a':'projection','b':'projection'})
    results['unregistered_exact_type']=reject(lambda:g.prepare(values),'unsupported exact primitive')
    return results


def preservation(root):
    manifest=json.loads((root/'preservation.json').read_text())
    for folder,entries in manifest.items():
        directory=root.parent/folder
        current={str(p.relative_to(directory)):hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.rglob('*') if p.is_file()}
        assert current==entries, f'Preserved example changed: {folder}'
    return {folder:len(entries) for folder,entries in manifest.items()}


def main(build, root):
    parser=argparse.ArgumentParser()
    parser.add_argument('--device',default='cpu')
    parser.add_argument('--inductor',action='store_true')
    args=parser.parse_args()
    root=Path(root); directory=root/'results'; directory.mkdir(exist_ok=True)
    torch.set_num_threads(1)
    torch.backends.cuda.matmul.allow_tf32=False; torch.backends.cudnn.allow_tf32=False
    from torch._inductor import config as inductor_config
    inductor_config.compile_threads=1
    result=dict(environment=dict(torch=torch.__version__,python=platform.python_version(),device=args.device,
                                 threads=1,tf32=False),cases={},library_reuse={},invalid_dependencies={})
    with torch.inference_mode():
        result['library_reuse']=generic_reuse(args.device)
        for label in CONFIGS:
            for dtype in ('float64','float32'):
                print('validate',label,dtype,args.device,'inductor',args.inductor,flush=True)
                result['cases'][label+'_'+dtype]=transformer_case(build,label,dtype,args.device,directory,args.inductor)
        result['invalid_dependencies']=invalid_graphs(build)
    result['preserved_files']=preservation(root)
    result['status']='passed'
    path=directory/('validation_'+args.device.replace(':','_')+'.json')
    path.write_text(json.dumps(result,indent=2)+'\n'); print('PASS',path,flush=True)
