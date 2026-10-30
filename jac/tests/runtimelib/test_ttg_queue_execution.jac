"""Exercise queue certificates inside the real OSP kernel with an in-memory backend."""
import from jaclang.runtime.osp_kernel {
    OspRuntime,
    NodeDesc,
    WalkerDesc,
    Slot,
    osp_spawn,
    osp_visit
}
import from jaclang.runtime.archetype { NodeAnchor }
import from jaclang.runtime.ttg_dependencies {
    analyze_walker_dependencies,
    decide_live_pending,
    pending_trace_queue
}
import from .fixtures.ttg_dependency_walkers {
    DepStart,
    DepA,
    DepB,
    DepD,
    DepQueueWalker
}

# The callbacks below lower the fixture's statements directly onto the portable
# kernel, placing the checkpoint after the assignment and before the continuation.
# This backend has no persistence or SQL access.
test "TTG queue execution: live checkpoint survives earlier A entries and deferred exits" {
    graph = analyze_walker_dependencies(DepQueueWalker);
    point = [
        e.id
        for e in graph.events
        if e.ability == 'on_start' and e.kind == 'assign' and e.writes == 'self.mode'
    ][0];
    source = NodeAnchor(archetype=DepStart(value=13), edges=[]);
    a1 = NodeAnchor(archetype=DepA(), edges=[]);
    a2 = NodeAnchor(archetype=DepA(), edges=[]);
    b = NodeAnchor(archetype=DepB(), edges=[]);
    extra = NodeAnchor(archetype=DepD(), edges=[]);
    observed: list = [];
    certificates: list = [];
    tags: dict[type, int] = {DepStart: 1, DepA: 2, DepB: 3, DepD: 4};
    enqueue: any = osp_visit;
    def tag(value: any) -> int {
        if isinstance(value, DepQueueWalker) {
            return 10;
        }
        return tags[type(value.archetype)];
    }
    def is_a(actual: int, expected: int) -> bool {
        return actual == expected;
    }
    def node_desc(tag: int) -> NodeDesc {
        return NodeDesc(type_tag=tag, `entry=[], `exit=[]);
    }
    def on_entry(w: any, current: any) {
        if isinstance(current.archetype, DepD) {
            observed.append('D');
        }
    }
    def complete(scope: any, ok: bool) { }
    def start(w: any, current: any) {
        w.mode = current.archetype.value;
        queue = pending_trace_queue();
        assert [item.node_type for item in queue] == [DepA, DepA, DepB];
        certificates.append(decide_live_pending(graph, point, 2, 'on_b'));
        w.counter = w.counter + 1;
        observed.append('start');
    }
    def a_entry(w: any, current: any) {
        w.counter = w.counter + 1;
        observed.append('A');
        if w.counter < 0 {
            enqueue([extra]);
        }
    }
    def a_exit(w: any, current: any) {
        w.mode = 0;
        observed.append('exit-A');
    }
    def b_entry(w: any, current: any) {
        observed.append('B:' + str(w.mode));
        assert w.mode > 10;
    }
    rt = OspRuntime(
        tag_of=tag,
        is_a=is_a,
        node_desc=node_desc,
        entry_hook=on_entry,
        on_complete=complete
    );
    descriptor = WalkerDesc(
        type_tag=10,
        `entry=[Slot(1, start), Slot(2, a_entry), Slot(3, b_entry)],
        `exit=[Slot(2, a_exit)]
    );
    run: any = osp_spawn;
    run(rt, DepQueueWalker(counter=-5), descriptor, [source, a1, a2, b]);
    decision = certificates[0];
    assert decision.stable , str(decision.reasons);
    assert decision.path_determined;
    assert decision.execution_preserved;
    assert decision.prediction.visits[0]['target_types'] == ('DepC', );
    assert observed == ['start', 'A', 'A', 'B:13', 'D', 'D', 'exit-A', 'exit-A'];
}
