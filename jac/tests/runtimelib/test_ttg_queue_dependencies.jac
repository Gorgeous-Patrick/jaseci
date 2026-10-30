import from jaclang.runtime.ttg_dependencies {
    analyze_walker_dependencies,
    PendingTraceNode
}
import from .fixtures.ttg_dependency_walkers {
    DepA,
    DepB,
    DepStart,
    DepHook,
    DepQueueWalker,
    DepQueueCancels,
    DepWalker,
    DepMutation,
    DepLoop,
    DepNeedsB,
    DepOverwrite
}

test "TTG queue: unrelated writes in two earlier A nodes preserve B path" {
    graph = analyze_walker_dependencies(DepQueueWalker);
    queue = [
        PendingTraceNode(DepA, 'a1'),
        PendingTraceNode(DepA, 'a2'),
        PendingTraceNode(DepB, 'b')
    ];
    result = graph.decide_pending(
        queue, 2, 'on_b', {'self.mode': 13, 'self.counter': 0}
    );
    assert result.stable , str(result.reasons);
    assert result.execution_preserved;
    assert result.path_determined;
    assert result.dependencies == ('self.mode', );
    assert result.intervening_writes == ('self.counter', );
    if result.prediction is not None {
        assert result.prediction.visits[0]['target_types'] == ('DepC', );
    }
}

test "TTG queue: earlier A writing mode invalidates a decision" {
    graph = analyze_walker_dependencies(DepWalker);
    result = graph.decide_pending(
        [PendingTraceNode(DepA), PendingTraceNode(DepB)], 1, 'on_b', {'self.mode': 13}
    );
    assert not result.stable;
    assert not result.path_determined;
    assert 'self.mode' in result.intervening_writes;
}

test "TTG queue: unrelated current continuation is allowed" {
    graph = analyze_walker_dependencies(DepQueueWalker);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'on_start' and e.writes == 'self.mode' and e.kind == 'assign'
    ][0];
    result = graph.decide_pending(
        [PendingTraceNode(DepA), PendingTraceNode(DepB)],
        1,
        'on_b',
        {'self.mode': 13, 'self.counter': 0},
        point=point,
        current_type=DepStart
    );
    assert result.stable , str(result.reasons);
    assert result.path_determined;
}

test "TTG queue: relevant current continuation blocks a decision" {
    graph = analyze_walker_dependencies(DepMutation);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'on_a' and e.kind == 'assign'
    ][0];
    result = graph.decide_pending(
        [PendingTraceNode(DepB)],
        0,
        'on_b',
        {'self.mode': 13},
        point=point,
        current_type=DepA
    );
    assert not result.stable;
}

test "TTG queue: cancellation separates path knowledge from target execution" {
    graph = analyze_walker_dependencies(DepQueueCancels);
    result = graph.decide_pending(
        [PendingTraceNode(DepA), PendingTraceNode(DepB)], 1, 'on_b', {'self.mode': 13}
    );
    assert result.stable , str(result.reasons);
    assert result.path_determined;
    assert not result.execution_preserved;
}

test "TTG queue: unknown effects and node entry handlers are barriers" {
    graph = analyze_walker_dependencies(DepLoop);
    result = graph.decide_pending(
        [PendingTraceNode(DepA), PendingTraceNode(DepA)], 1, 'on_a', {'self.mode': 13}
    );
    assert not result.stable;
    graph = analyze_walker_dependencies(DepQueueWalker);
    result = graph.decide_pending(
        [PendingTraceNode(DepHook), PendingTraceNode(DepB)],
        1,
        'on_b',
        {'self.mode': 13}
    );
    assert not result.stable;
}

test "TTG queue: stable state still needs B node inputs" {
    graph = analyze_walker_dependencies(DepNeedsB);
    result = graph.decide_pending(
        [PendingTraceNode(DepB)], 0, 'on_b', {'self.mode': 13}
    );
    assert result.stable;
    assert result.execution_preserved;
    assert not result.path_determined;
    assert 'on_b::here.enabled' in result.dependencies;
}

test "TTG queue: B overwrite removes irrelevant incoming mode dependency" {
    graph = analyze_walker_dependencies(DepOverwrite);
    result = graph.decide_pending(
        [PendingTraceNode(DepA), PendingTraceNode(DepB)], 1, 'on_b', {'self.mode': 13}
    );
    assert result.stable , str(result.reasons);
    assert result.dependencies == ();
    assert result.path_determined;
}
