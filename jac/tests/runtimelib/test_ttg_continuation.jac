"""Whole-TTG continuation proofs with an independent ordered topology oracle."""
import from jaclang.runtime.ttg { JacTTGGenerator }
import from jaclang.runtime.ttg_dependencies { analyze_walker_dependencies }
import from .fixtures.ttg_continuation_walkers {
    ContinueA,
    ContinueB,
    ContinueC,
    ContinueD,
    ContinueChain,
    ContinueUnknown,
    ContinueCancel,
    ContinueCycle,
    ContinueAppend,
    ContinueSourceCancel,
    ContinueExit,
    ContinueCustom
}

test "TTG continuation validates builtin list receivers before passing append effects" {
    graph = analyze_walker_dependencies(ContinueAppend);
    current = {'id': 'a', 'node_type': ContinueA};
    known = JacTTGGenerator.get_continuation_plan(
        graph,
        current,
        graph.entries['first'],
        {'self.seen::list': True},
        [],
        continuation_resolver
    );
    assert known['complete'] , str(known);
    assert known['executions'] == ['ContinueB', 'ContinueC'];
    unknown = JacTTGGenerator.get_continuation_plan(
        graph, current, graph.entries['first'], {}, [], continuation_resolver
    );
    assert not unknown['complete'];
    assert unknown['executions'] == ['ContinueB'];
    assert 'append' in unknown['stop'];
}

test "TTG continuation distinguishes eager visit payload demand from cancelled dispatch" {
    graph = analyze_walker_dependencies(ContinueSourceCancel);
    calls: list = [];
    def resolve(active: dict, event: any) -> list[dict] {
        calls.append(event.id);
        return continuation_resolver(active, event);
    }
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {},
        [],
        resolve
    );
    assert not result['complete'];
    assert result['executions'] == [];
    assert [item['id'] for item in result['nodes']] == ['ContinueB'];
    assert len(calls) == 1;
}

test "TTG continuation uses known queued node fields before an independent successor" {
    graph = analyze_walker_dependencies(ContinueUnknown);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'first' and e.kind == 'visit'
    ][0];
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        point,
        {'self.count': 7},
        [
            {'id': 'b', 'node_type': ContinueB, 'facts': {'value': 0}},
            {'id': 'c', 'node_type': ContinueC}
        ],
        continuation_resolver
    );
    assert result['complete'] , str(result);
    assert result['executions'] == ['b', 'c', 'ContinueD'];
    assert [item['id'] for item in result['nodes']] == ['ContinueD'];
}

test "TTG continuation marks a truncated pending queue incomplete" {
    graph = analyze_walker_dependencies(ContinueChain);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'first' and e.kind == 'visit'
    ][0];
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA, 'pending_truncated': True},
        point,
        {'self.count': 0},
        [{'id': 'd', 'node_type': ContinueD}],
        continuation_resolver,
        max_nodes=1
    );
    assert result['executions'] == ['d'];
    assert not result['complete'];
    assert 'budget' in result['stop'];
}

test "TTG continuation treats custom node attribute access as an unknown effect" {
    graph = analyze_walker_dependencies(ContinueChain);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueCustom},
        graph.entries['first'],
        {'self.count': 0},
        [],
        continuation_resolver
    );
    assert not result['complete'];
    assert result['nodes'] == [];
    assert 'attribute access' in result['stop'];
}

test "native visit loads its full batch even when queued abilities are cancelled" {
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            target = str(Path(project, 'eager_visit.jac'));
            seed = ExecutionContext(base_path_dir=project, full_target_path=target);
            JacRuntime.exec_ctx = seed;
            a = ContinueA();
            root ++> a;
            future_ids: set = set();
            for i in range(3) {
                b = ContinueB(value=i);
                a ++> b;
                future_ids.add(b.__jac__.id);
            }
            start_id = a.__jac__.id;
            seed.close();
            for prefetch in [False, True] {
                ctx = ExecutionContext(base_path_dir=project, full_target_path=target);
                JacRuntime.exec_ctx = ctx;
                try {
                    anchor = ctx.mem.get(start_id);
                    assert anchor is not None;
                    origin = anchor.archetype;
                    assert isinstance(origin, ContinueA);
                    assert not (future_ids & set(ctx.mem.__mem__));
                    wlk = ContinueSourceCancel();
                    if prefetch {
                        with dependency_prefetch(ctx, mode='') as run {
                            origin spawn wlk;
                        }
                        assert run.submitted == future_ids , str(run.summary());
                        assert run.promoted == future_ids , str(run.summary());
                    } else {
                        origin spawn wlk;
                    }
                    assert not wlk.entered;
                    assert future_ids <= set(ctx.mem.__mem__);
                } finally {
                    ctx.close();
                }
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "TTG continuation identifies outstanding exit callbacks at the entry frontier" {
    graph = analyze_walker_dependencies(ContinueExit);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {},
        [],
        continuation_resolver
    );
    assert result['executions'] == ['ContinueB'];
    assert not result['complete'];
    assert 'Exit callbacks' in result['stop'];
}

import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.runtime.context { ExecutionContext }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.runtime.ttg_dependency_prefetch { dependency_prefetch }

def continuation_resolver(active: dict, event: any) -> list[dict] {
    types = {'ContinueB': ContinueB, 'ContinueC': ContinueC, 'ContinueD': ContinueD};
    target = event.targets[0];
    return [{'id': target, 'node_type': types[target]}];
}

test "TTG continuation follows three future abilities with propagated scalar state" {
    graph = analyze_walker_dependencies(ContinueChain);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {'self.count': 0},
        [],
        continuation_resolver
    );
    assert result['complete'] , str(result);
    assert result['executions'] == ['ContinueB', 'ContinueC', 'ContinueD'];
    assert len(result['paths']) == 3;
}

test "TTG continuation respects existing FIFO entries before newly visited nodes" {
    graph = analyze_walker_dependencies(ContinueChain);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {'self.count': 0},
        [{'id': 'queued-b', 'node_type': ContinueB}],
        continuation_resolver
    );
    assert result['complete'] , str(result);
    assert result['executions']
        == ['queued-b', 'ContinueB', 'ContinueC', 'ContinueD', 'ContinueD'] , str(
        result
    );
    assert [item['taken'] for item in result['branches']] == [True, False];
}

test "TTG continuation stops at unknown node data and resumes after a runtime hook" {
    graph = analyze_walker_dependencies(ContinueUnknown);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {'self.count': 0},
        [],
        continuation_resolver
    );
    assert not result['complete'];
    assert result['executions'] == ['ContinueB'];
    assignment = [
        e.id
        for e in graph.events
        if e.ability == 'second' and e.kind == 'assign'
    ][0];
    resumed = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'ContinueB', 'node_type': ContinueB},
        assignment,
        {'self.count': 1},
        [],
        continuation_resolver
    );
    assert resumed['complete'] , str(resumed);
    assert resumed['executions'] == ['ContinueC', 'ContinueD'];
}

test "TTG continuation cancellation prevents speculative visits behind the queue head" {
    graph = analyze_walker_dependencies(ContinueCancel);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {},
        [{'id': 'stop', 'node_type': ContinueB}, {'id': 'c', 'node_type': ContinueC}],
        continuation_resolver
    );
    assert not result['complete'];
    assert result['executions'] == ['stop'];
    assert result['stop'].startswith('cancel');
}

test "TTG continuation repeated node identities preserve distinct state transitions" {
    graph = analyze_walker_dependencies(ContinueCycle);
    result = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {'self.count': 0},
        [],
        continuation_resolver
    );
    assert result['complete'] , str(result);
    assert result['executions'] == ['ContinueB', 'ContinueB', 'ContinueB'];
    limited = JacTTGGenerator.get_continuation_plan(
        graph,
        {'id': 'a', 'node_type': ContinueA},
        graph.entries['first'],
        {'self.count': 0},
        [],
        continuation_resolver,
        max_nodes=1
    );
    assert not limited['complete'];
    assert limited['executions'] == ['ContinueB'];
    assert 'budget' in limited['stop'];
}

test "automatic entry hook invokes whole TTG and prefetches three future abilities" {
    original = JacRuntime.exec_ctx;
    try {
        for mode in ['', 'thread', 'process'] {
            with TemporaryDirectory() as project {
                target = str(Path(project, 'continuation.jac'));
                seed = ExecutionContext(base_path_dir=project, full_target_path=target);
                JacRuntime.exec_ctx = seed;
                a = ContinueA();
                b = ContinueB();
                c = ContinueC();
                d = ContinueD();
                root ++> a;
                a ++> b;
                b ++> c;
                c ++> d;
                start_id = a.__jac__.id;
                future_ids = {b.__jac__.id, c.__jac__.id, d.__jac__.id};
                seed.close();
                ctx = ExecutionContext(base_path_dir=project, full_target_path=target);
                JacRuntime.exec_ctx = ctx;
                try {
                    anchor = ctx.mem.get(start_id);
                    assert anchor is not None;
                    origin = anchor.archetype;
                    assert isinstance(origin, ContinueA);
                    wlk = ContinueChain();
                    with dependency_prefetch(ctx, mode=mode) as run {
                        origin spawn wlk;
                    }
                    assert wlk.count == 1;
                    assert run.submitted == future_ids , str(run.summary());
                    assert run.promoted == future_ids , str(run.summary());
                    assert run.continuations[0]['complete'] , str(run.summary());
                    assert len(run.continuations[0]['paths']) == 3;
                    assert not run.errors , str(run.errors);
                    assert not any('payload_error' in plan for plan in run.plans) , str(
                        run.summary()
                    );
                } finally {
                    ctx.close();
                }
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}
