import from unittest { TestCase }
import from jaclang.runtime.ttg_dependencies { analyze_walker_dependencies }
import from .fixtures.ttg_dependency_walkers {
    DepWalker,
    DepNeedsB,
    DepMutation,
    DepMerge,
    DepOverwrite,
    DepLoop,
    DepMultipleHandlers
}

test "TTG dependencies: data control dispatch and transported walker state" {
    graph = analyze_walker_dependencies(DepWalker);
    assert set(e.kind for e in graph.edges)
        >= {'data', 'control', 'dispatch', 'state', 'order'};
    definitions = [
        e
        for e in graph.events
        if e.ability == 'on_a' and e.writes == 'self.mode' and e.kind == 'assign'
    ];
    guards = [
        e
        for e in graph.events
        if e.ability == 'on_b' and e.kind == 'branch'
    ];
    links = [
        e
        for e in graph.edges
        if e.kind == 'state'
            and e.source == definitions[0].id
            and e.target == guards[0].id
    ];
    assert len(links) == 1;
    assert graph.events[links[0].context].kind == 'visit';
    assert 'DepB' in graph.events[links[0].context].targets;
}

test "TTG dependencies: checkpoint predicts both B paths and skipped visit" {
    graph = analyze_walker_dependencies(DepWalker);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'on_a' and e.writes == 'self.mode' and e.kind == 'assign'
    ][0];
    for (value, expected) in [
        (13, ['DepB', 'DepC']),
        (3, ['DepB', 'DepD']),
        (-1, [])
    ] {
        result = graph.predict_after(point, {'self.mode': value}, isolated=True);
        assert result.complete , str(result.unresolved);
        assert [v['target_type'] for v in result.visits] == expected;
    }
}

test "TTG dependencies: A-local computation can be replayed from earlier point" {
    graph = analyze_walker_dependencies(DepWalker);
    point = [
        e.id
        for e in graph.events
        if e.writes == 'on_a::x' and e.kind == 'assign'
    ][0];
    result = graph.predict_after(point, {'on_a::x': 12}, isolated=True);
    assert result.complete , str(result.unresolved);
    assert [v['target_type'] for v in result.visits] == ['DepB', 'DepC'];
}

test "TTG dependencies: B field remains unresolved at A checkpoint" {
    graph = analyze_walker_dependencies(DepNeedsB);
    point = [
        e.id
        for e in graph.events
        if e.kind == 'assign'
    ][0];
    result = graph.predict_after(point, {'self.mode': 12}, isolated=True);
    assert not result.complete;
    assert 'on_b::here.enabled' in result.unresolved[0];
}

test "TTG dependencies: queued transition cannot bypass later writes" {
    graph = analyze_walker_dependencies(DepMutation);
    point = [
        e.id
        for e in graph.events
        if e.kind == 'assign'
    ][0];
    result = graph.predict_after(point, {'self.mode': 12}, isolated=True);
    assert not result.complete;
    assert 'continuation' in result.unresolved[0];
}

test "TTG dependencies: conditional definitions join through phi" {
    graph = analyze_walker_dependencies(DepMerge);
    assert any(e.kind == 'phi' and e.writes == 'self.mode' for e in graph.events);
    point = [
        e.id
        for e in graph.events
        if e.kind == 'assign'
    ][0];
    for (value, expected) in [(1, 'DepC'), (-1, 'DepD')] {
        result = graph.predict_after(point, {'self.mode': value}, isolated=True);
        assert result.complete , str(result.unresolved);
        assert result.visits[-1]['target_type'] == expected;
    }
}

test "TTG dependencies: B overwrite kills transported definition" {
    graph = analyze_walker_dependencies(DepOverwrite);
    guard = [
        e
        for e in graph.events
        if e.ability == 'on_b' and e.kind == 'branch'
    ][0];
    assert not any(e.kind == 'state' and e.target == guard.id for e in graph.edges);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'on_a' and e.kind == 'assign'
    ][0];
    result = graph.predict_after(point, {'self.mode': 12}, isolated=True);
    assert result.complete;
    assert [v['target_type'] for v in result.visits] == ['DepB'];
}

test "TTG dependencies: unknown effects and ambiguous handlers block prediction" {
    for walker_type in [DepLoop, DepMultipleHandlers] {
        graph = analyze_walker_dependencies(walker_type);
        point = [
            e.id
            for e in graph.events
            if e.kind == 'assign'
        ][0];
        assert not graph.predict_after(
            point, {'self.mode': 12}, isolated=True
        ).complete;
    }
}

test "TTG dependencies: explicit snapshot contract and missing inputs" {
    graph = analyze_walker_dependencies(DepWalker);
    point = [
        e.id
        for e in graph.events
        if e.writes == 'self.mode' and e.kind == 'assign'
    ][0];
    assert not graph.predict_after(point, {'self.mode': 12}).complete;
    assert not graph.predict_after(point, {}, isolated=True).complete;
    with TestCase().assertRaises(ValueError) {
        graph.predict_after(point, {'self.mode': object()}, isolated=True);
    }
}
