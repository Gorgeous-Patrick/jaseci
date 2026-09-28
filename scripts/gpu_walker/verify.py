"""Compare CPU lowering against real serial Jac walkers; emit but never run PTX."""

import argparse
import ctypes
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys
import tempfile


SERIAL_REFERENCE = """
def serial_sums(values: list[float], links: list[int], heads: list[int],
                initial: list[float]) -> list[float] {
    nodes = [Cell(value=value) for value in values];
    for i in range(len(nodes)) {
        if links[i] != -1 {
            nodes[i] +>:Next():+> nodes[links[i]];
        }
    }
    results: list[float] = [];
    for i in range(len(heads)) {
        visitor = ChainSum(total=initial[i]);
        if heads[i] != -1 {
            nodes[heads[i]] spawn visitor;
        }
        results.append(visitor.total);
    }
    return results;
}
"""


def same(actual, expected):
    assert len(actual) == len(expected)
    for i, (a, b) in enumerate(zip(actual, expected)):
        if math.isnan(b):
            assert math.isnan(a), (i, a, b)
        else:
            assert struct.pack('=d', a) == struct.pack('=d', b), (i, a, b)


class CpuKernel:
    """A CPU lane entry with the same traversal/body lowering, not a GPU emulator."""

    def __init__(self, walker):
        from jaclang.compiler.backends.native.ptx_walker import build_chain_module
        from jaclang.compiler.backends.native.llvm import binding as llvm

        self.target = llvm.Target.from_default_triple().create_target_machine(opt=2)
        module = build_chain_module([walker], self.target, device=False)
        self.ir = str(module)
        self.engine = llvm.create_mcjit_compiler(module, self.target)
        self.engine.finalize_object()
        signature = [ctypes.POINTER(t) for t in (
            ctypes.c_double, ctypes.c_int64, ctypes.c_int64, ctypes.c_double,
            ctypes.c_double, ctypes.c_uint32,
        )] + [ctypes.c_uint64] * 3
        self.lane = ctypes.CFUNCTYPE(None, *signature)(
            self.engine.get_function_address(f'jac_{walker.name}_lane'))

    def run(self, values, links, heads, initial):
        n, m = len(values), len(heads)
        assert len(links) == n and len(initial) == m
        inputs = [(typ * len(items))(*items) for typ, items in (
            (ctypes.c_double, values), (ctypes.c_int64, links),
            (ctypes.c_int64, heads), (ctypes.c_double, initial),
        )]
        before = [bytes(buf) for buf in inputs]
        output = (ctypes.c_double * (m + 2))(*([-987654.25] * (m + 2)))
        status = (ctypes.c_uint32 * (m + 2))(*([173] * (m + 2)))
        out_ptr = ctypes.cast(ctypes.byref(output, 8), ctypes.POINTER(ctypes.c_double))
        status_ptr = ctypes.cast(ctypes.byref(status, 4), ctypes.POINTER(ctypes.c_uint32))
        # Deliberately reverse execution order to expose shared mutable state.
        for lane in reversed(range(m)):
            self.lane(*inputs, out_ptr, status_ptr, n, m, lane)
        for count, index in ((0, 0), (m, m), (m, 2**32), (m, 2**64 - 1)):
            self.lane(*([None] * 6), n, count, index)
        assert output[0] == output[-1] == -987654.25
        assert status[0] == status[-1] == 173
        assert before == [bytes(buf) for buf in inputs], 'Read-only inputs were modified'
        return list(output)[1:-1], list(status)[1:-1]


def reorder_nodes(values, links, heads, order):
    """order[new_slot] = old_slot; keep every logical node exactly once."""
    assert sorted(order) == list(range(len(values)))
    old_to_new = {old: new for new, old in enumerate(order)}
    return (
        [values[old] for old in order],
        [-1 if links[old] == -1 else old_to_new[links[old]] for old in order],
        [-1 if head == -1 else old_to_new[head] for head in heads],
    )


def batches():
    # Empty graph, empty traversal, a single node, and a shared suffix.
    yield [], [], [], []
    yield [], [], [-1], [-0.0]
    yield [2.5], [-1], [0], [7.0]
    yield [1e16, -1e16, 1.0, -3.5], [1, 2, -1, 1], [0, 1, 3, -1, 0], [0.0, 4.0, -2.0, 9.0, 3.0]
    edge = [-0.0, 2.0**-1074, -2.0**-1074, math.inf, -math.inf, math.nan]
    yield edge, [-1] * len(edge), list(range(len(edge))), [-0.0] * len(edge)
    rng = random.Random(928)
    for m in (0, 1, 31, 32, 33, 257, 1024):
        # Acyclic graph with merging paths and nonuniform traversal lengths.
        n = 71
        values = [rng.uniform(-1e6, 1e6) for _ in range(n)]
        links = [rng.choice([-1] + list(range(i + 1, n))) for i in range(n)]
        heads = [rng.randrange(-1, n) for _ in range(m)]
        initial = [rng.uniform(-10.0, 10.0) for _ in range(m)]
        yield values, links, heads, initial


def verify(repo: Path, output: Path):
    """Keep graph comparisons independent of a CLI/test runner's database context."""
    from jaclang.runtime.context import ExecutionContext
    from jaclang.runtime.memory import Memory
    from jaclang.runtime.runtime import JacRuntime

    base = JacRuntime.get_base_path_dir()
    target = JacRuntime.get_full_target_path()
    try:
        JacRuntime.set_base_path(None)
        JacRuntime.set_full_target_path(None)
        context = ExecutionContext()
    finally:
        JacRuntime.set_base_path(base)
        JacRuntime.set_full_target_path(target)
    assert type(context.mem) is Memory
    token = JacRuntime.push_request_context(context)
    try:
        return _verify(repo, output)
    finally:
        try:
            context.close()
        finally:
            JacRuntime.reset_request_context(token)


def _verify(repo: Path, output: Path):
    from jaclang.compiler.backends.native.ptx import (
        PtxUnsupported, compile_ptx_frontend,
    )
    from jaclang.compiler.backends.native.ptx_walker import (
        select_chain_walkers, emit_chain_ptx,
    )
    from jaclang.compiler.backends.native.llvm import binding as llvm
    from jaclang.runtime.runtime import JacRuntime

    llvm.initialize_all_targets()
    llvm.initialize_all_asmprinters()
    source_path = repo / 'jac/examples/gpu/chain.jac'
    source = source_path.read_text()
    selected = select_chain_walkers(compile_ptx_frontend(str(source_path)), ['ChainSum'])
    artifact = emit_chain_ptx(selected)
    kernel = CpuKernel(selected[0])
    output.mkdir(parents=True, exist_ok=True)
    (output / 'chain.ptx').write_text(artifact.ptx)
    (output / 'chain.gpu.ll').write_text(artifact.llvm_ir)
    (output / 'chain.cpu-check.ll').write_text(kernel.ir)
    assert artifact.format == 'jac-ptx-chain-v1'
    assert '.entry jac_ChainSum_batch(' in artifact.ptx
    assert all(reg in artifact.ptx for reg in ('%tid.x', '%ntid.x', '%ctaid.x'))
    assert 'addrspace(1)' in artifact.llvm_ir
    assert not any(word in artifact.ptx for word in ('__jac_', 'osp_', '.extern .func', 'fma.rn.f64'))
    counts = dict(cpu_walker_results=0, cpu_layout_results=0, cpu_batch_checks=0,
                  cpu_invalid_graph_checks=0, cpu_changed_source_results=0)
    with tempfile.TemporaryDirectory(prefix='jac-chain-verify-') as tmp:
        tmp_path = Path(tmp)
        serial_path = tmp_path / 'serial_chain.jac'
        serial_path.write_text(source + SERIAL_REFERENCE)
        reference = JacRuntime.jac_import(target='serial_chain', base_path=tmp)[0]
        for values, links, heads, initial in batches():
            expected = list(reference.serial_sums(values, links, heads, initial))
            actual, status = kernel.run(values, links, heads, initial)
            assert status == [0] * len(heads)
            same(actual, expected)
            counts['cpu_walker_results'] += len(heads)
            counts['cpu_batch_checks'] += 1
            order = list(range(len(values)))
            random.Random(924).shuffle(order)
            remapped = reorder_nodes(values, links, heads, order)
            # Reorder walker slots too, then restore their logical output order.
            walker_order = list(reversed(range(len(heads))))
            actual, status = kernel.run(remapped[0], remapped[1],
                [remapped[2][i] for i in walker_order], [initial[i] for i in walker_order])
            assert status == [0] * len(heads)
            restored = [0.0] * len(heads)
            for slot, old in enumerate(walker_order):
                restored[old] = actual[slot]
            same(restored, expected)
            counts['cpu_layout_results'] += len(heads)

        # The four-chain Ours example, with nonuniform node values and state.
        values = [float(i + 1) for i in range(12)]
        links = [1, 2, -1, 4, 5, -1, 7, 8, -1, 10, 11, -1]
        heads, initial = [0, 3, 6, 9], [0.0, 10.0, 20.0, 30.0]
        ours_order = [0, 3, 6, 9, 1, 4, 7, 10, 2, 5, 8, 11]
        packed = reorder_nodes(values, links, heads, ours_order)
        expected = list(reference.serial_sums(values, links, heads, initial))
        actual, status = kernel.run(*packed, initial)
        assert status == [0] * 4
        same(actual, expected)
        counts['cpu_layout_results'] += 4
        (output / 'four_walkers.inputs.json').write_text(json.dumps({
            'values': packed[0], 'next': packed[1], 'heads': packed[2],
            'initial_total': initial, 'expected_results': expected,
            'node_count': 12, 'walker_count': 4, 'gpu_executed': False,
        }, indent=2) + '\n')

        bad_cases = [([], [], [0], 1), ([1.0], [-1], [-2], 1),
                     ([1.0], [-1], [1], 1), ([1.0], [1], [0], 1),
                     ([1.0], [-2], [0], 1), ([1.0], [0], [0], 2),
                     ([1.0, 2.0], [1, 0], [0, 1], 2)]
        for values, links, heads, code in bad_cases:
            actual, status = kernel.run(values, links, heads, [0.0] * len(heads))
            assert status == [code] * len(heads), (values, links, heads, status)
            assert actual == [-987654.25] * len(heads), actual
            counts['cpu_invalid_graph_checks'] += len(heads)

        changed_source = source.replace('self.total += here.value;',
            'self.total = self.total - (here.value * 2.0 + -1.0);')
        changed_path = tmp_path / 'changed_chain.jac'
        changed_path.write_text(changed_source + SERIAL_REFERENCE)
        changed = select_chain_walkers(compile_ptx_frontend(str(changed_path)), ['ChainSum'])
        changed_artifact = emit_chain_ptx(changed)
        assert changed_artifact.ptx != artifact.ptx
        changed_reference = JacRuntime.jac_import(target='changed_chain', base_path=tmp)[0]
        changed_kernel = CpuKernel(changed[0])
        changed_expected = list(changed_reference.serial_sums(values := [2.0, 3.0, 5.0],
            links := [1, 2, -1], heads := [0, 1, -1], initial := [0.0, 7.0, -0.0]))
        actual, status = changed_kernel.run(values, links, heads, initial)
        same(actual, changed_expected)
        assert status == [0, 0, 0] and actual[0] == -17.0
        counts['cpu_changed_source_results'] += len(heads)
        (output / 'changed_chain.ptx').write_text(changed_artifact.ptx)

        # Names and defaults come from the source schema, not the demonstration.
        renamed_source = source.replace('self.total += here.value;', 'self.total *= here.value;')
        renamed_source = (renamed_source + SERIAL_REFERENCE).replace('ChainSum', 'ChainProduct')
        for old, new in (('Cell', 'Vertex'), ('Next', 'Link'), ('total', 'product'), ('value', 'weight')):
            renamed_source = renamed_source.replace(old, new)
        renamed_source = renamed_source.replace('product: float = 0.0;', 'product: float = 1.0;')
        renamed_path = tmp_path / 'renamed_chain.jac'
        renamed_path.write_text(renamed_source)
        renamed = select_chain_walkers(compile_ptx_frontend(str(renamed_path)), ['ChainProduct'])
        renamed_artifact = emit_chain_ptx(renamed)
        metadata = renamed_artifact.kernels[0]
        assert (metadata['node_type'], metadata['edge_type'], metadata['node_field'],
                metadata['state_field'], metadata['default_initial_state']) == ('Vertex', 'Link', 'weight', 'product', 1.0)
        renamed_reference = JacRuntime.jac_import(target='renamed_chain', base_path=tmp)[0]
        renamed_kernel = CpuKernel(renamed[0])
        initial = [1.0, 2.0, -0.0]
        expected = list(renamed_reference.serial_sums(values, links, heads, initial))
        actual, status = renamed_kernel.run(values, links, heads, initial)
        same(actual, expected)
        assert actual[0] == 30.0 and status == [0, 0, 0]
        counts['cpu_changed_source_results'] += len(heads)

        rejected = {}
        variants = {
            'node_write': source.replace('self.total += here.value;', 'here.value += 1.0;'),
            'report': source.replace('visit [->:Next:->];', 'report self.total; visit [->:Next:->];'),
            'non_tail_visit': source.replace('self.total += here.value;\n        visit [->:Next:->];',
                'visit [->:Next:->];\n        self.total += here.value;'),
            'division': source.replace('here.value;', 'here.value / 2.0;'),
            'integer_field': source.replace('value: float;', 'value: int;'),
            'untyped_edge': source.replace('[->:Next:->]', '[-->]'),
            'incoming_edge': source.replace('[->:Next:->]', '[<--]'),
            'static_state': source.replace('has total:', 'static has total:'),
            'extra_ability': source.replace('can step with Cell entry {',
                'can finish with Cell exit {}\n    can step with Cell entry {'),
            'node_ability': source.replace('has value: float;',
                'has value: float;\n    can observe with ChainSum entry {}'),
            'helper_call': source.replace('here.value;', 'helper(here.value);')
                + '\ndef helper(x: float) -> float { return x; }\n',
            'state_without_default': source.replace('total: float = 0.0;', 'total: float;'),
        }
        for name, text in variants.items():
            path = tmp_path / f'reject_{name}.jac'
            path.write_text(text)
            try:
                select_chain_walkers(compile_ptx_frontend(str(path)), ['ChainSum'])
            except PtxUnsupported as error:
                rejected[name] = str(error)
            else:
                raise AssertionError(f'Unsupported walker accepted: {name}')

    report = {
        'source': str(source_path), 'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'llvm_version': list(llvm.llvm_version_info), 'kernels': artifact.kernels,
        'ptx_emitted': True, 'llvm_verified': True, **counts,
        'reference': 'original Jac walkers on the ordinary serial runtime with in-memory storage',
        'cpu_execution': 'one supplied lane index at a time; not GPU simulation',
        'rejected_sources': rejected, 'gpu_executed': False,
    }
    (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--shim', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.repo / 'scripts/gpu_scalar'))
    from bootstrap import bootstrap
    bootstrap(args.repo, args.shim, args.cache)
    report = verify(args.repo, args.output)
    print(json.dumps({k: v for k, v in report.items() if k.startswith('cpu_') or k == 'gpu_executed'}, indent=2))
