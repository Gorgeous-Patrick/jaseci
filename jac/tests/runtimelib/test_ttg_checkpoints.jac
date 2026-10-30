"""Compile ordinary Jac walkers and observe automatically inserted checkpoints."""
import json;
import from unittest { TestCase }
import from jaclang.runtime.osp_kernel { osp_spawn }
import from jaclang.runtime.osp_kernel_sv { make_sv_runtime, desc_for }
import from jaclang.runtime.ttg_checkpoints { capture_dependency_checkpoints }
import from jaclang.runtime.ttg_dependencies {
    analyze_walker_dependencies,
    compile_checkpoint_plan,
    checkpoint_graph
}
import from .fixtures.ttg_dependency_walkers {
    DepA,
    DepB,
    DepC,
    DepD,
    DepStart,
    DepWalker,
    DepMutation,
    DepNeedsB,
    DepQueueWalker,
    DepQueueCancels
}

# Use the production server dispatch descriptors and compiled Jac callback bodies.
# Only completion persistence is omitted: these graphs are transient fixtures.
def run_checkpoint_walk(wlk: any, nodes: list) -> list[str] {
    rt = make_sv_runtime();
    observed: list[str] = [];
    def entered(wlk: any, current: any) {
        observed.append(type(current.archetype).__name__);
    }
    rt.entry_hook = entered;
    def done(scope: any, ok: bool) { }
    rt.on_complete = done;
    run: any = osp_spawn;
    run(rt, wlk, desc_for(type(wlk)), [n.__jac__ for n in nodes]);
    return observed;
}

test "TTG hooks: compiler plan selects relevant fields and typed visits" {
    import from jaclang.runtime.ttg { JacTTGGenerator }
    arch = JacTTGGenerator._find_walker_ast_node(DepWalker);
    assert arch is not None;
    plan = compile_checkpoint_plan(arch);
    selected = [plan['events'][i] for i in plan['points']];
    assert any(e['kind'] == 'assign' and e['writes'] == 'self.mode' for e in selected);
    assert not any(e['writes'] == 'on_a::x' for e in selected);
    assert any(e['kind'] == 'visit' for e in selected);
    restored = checkpoint_graph(json.loads(json.dumps(plan)), DepWalker);
    original = analyze_walker_dependencies(DepWalker);
    assert len(restored.events) == len(original.events);
    assert restored.predict_handler('on_b', {'self.mode': 13}).visits[0]['target_types']
        == ('DepC', );
}

test "TTG hooks: ordinary compiled walker predicts both branches after enqueue" {
    for (value, expected) in [(6, 'DepC'), (1, 'DepD')] {
        a = DepA(value=value);
        b = DepB();
        c = DepC();
        d = DepD();
        a ++> b;
        b ++> c;
        b ++> d;
        with capture_dependency_checkpoints() as capture {
            observed = run_checkpoint_walk(DepWalker(), [a]);
        }
        assert observed == ['DepA', 'DepB', expected];
        assert len(capture.hits) > 0 , 'Compiled handler did not execute an automatic hook';
        records = [
            r
            for r in capture.records
            if r['source_ability'] == 'on_a' and r['target_ability'] == 'on_b'
        ];
        assert len(records) == 1;
        decision = records[0]['decision'];
        assert records[0]['kind'] == 'visit';
        assert decision.stable
            and decision.path_determined
            and decision.execution_preserved , str(decision.reasons);
        assert decision.prediction.visits[0]['target_types'] == (expected, );
    }
}

test "TTG hooks: skipped source branch does not fabricate queued B" {
    a = DepA(value=-1);
    a ++> DepB();
    with capture_dependency_checkpoints() as capture {
        observed = run_checkpoint_walk(DepWalker(), [a]);
    }
    assert observed == ['DepA'];
    assert len(capture.hits) == 1;
    assert capture.hits[0]['kind'] == 'assign';
    assert capture.records == [];
}

test "TTG hooks: future overwrite blocks enqueue checkpoint and later assignment retries" {
    a = DepA(value=13);
    b = DepB();
    a ++> b;
    b ++> DepC();
    with capture_dependency_checkpoints() as capture {
        observed = run_checkpoint_walk(DepMutation(), [a]);
    }
    assert observed == ['DepA', 'DepB'];
    records = [
        r
        for r in capture.records
        if r['target_ability'] == 'on_b'
    ];
    assert len(records) == 2;
    assert records[0]['kind'] == 'visit';
    assert not records[0]['decision'].stable;
    assert 'self.mode' in records[0]['decision'].intervening_writes;
    assert records[1]['kind'] == 'assign';
    assert records[1]['decision'].stable and records[1]['decision'].path_determined , str(
        records[1]['decision'].reasons
    );
    assert records[1]['decision'].prediction.visits == [];
}

test "TTG hooks: source assignment can certify queued B across unrelated A entries" {
    w = DepQueueWalker(counter=-5);
    b = DepB();
    b ++> DepC();
    b ++> DepD();
    with capture_dependency_checkpoints() as capture {
        observed = run_checkpoint_walk(w, [DepStart(value=13), DepA(), DepA(), b]);
    }
    assert observed == ['DepStart', 'DepA', 'DepA', 'DepB', 'DepC'];
    records = [
        r
        for r in capture.records
        if r['source_ability'] == 'on_start' and r['target_ability'] == 'on_b'
    ];
    assert len(records) >= 1;
    assert records[0]['target_index'] == 2;
    assert records[0]['decision'].stable;
    assert records[0]['decision'].prediction.visits[0]['target_types'] == ('DepC', );
    # Deferred exits execute after B and may then change mode.
    assert w.mode == 0;
}

test "TTG hooks: unresolved target fields remain unresolved" {
    a = DepA(value=13);
    a ++> DepB(enabled=True);
    with capture_dependency_checkpoints() as capture {
        run_checkpoint_walk(DepNeedsB(), [a]);
    }
    records = [
        r
        for r in capture.records
        if r['target_ability'] == 'on_b'
    ];
    assert len(records) == 1;
    assert records[0]['decision'].stable;
    assert not records[0]['decision'].path_determined;
    assert 'on_b::here.enabled' in str(records[0]['decision'].reasons);
}

test "TTG hooks: nested captures restore the outer capture" {
    a = DepA(value=6);
    a ++> DepB();
    with capture_dependency_checkpoints() as outer {
        run_checkpoint_walk(DepWalker(), [a]);
        count = len(outer.hits);
        with capture_dependency_checkpoints() as inner {
            run_checkpoint_walk(DepWalker(), [a]);
        }
        assert len(inner.hits) > 0;
        assert len(outer.hits) == count;
        run_checkpoint_walk(DepWalker(), [a]);
        assert len(outer.hits) == count * 2;
    }
}

test "TTG hooks: relevant preceding write blocks source then retries after overwrite" {
    import from .fixtures.ttg_checkpoint_walkers { HookRelevantQueue }
    b = DepB();
    b ++> DepC();
    b ++> DepD();
    with capture_dependency_checkpoints() as capture {
        observed = run_checkpoint_walk(
            HookRelevantQueue(), [DepStart(value=13), DepA(), b]
        );
    }
    assert observed == ['DepStart', 'DepA', 'DepB', 'DepD'];
    records = [
        r
        for r in capture.records
        if r['target_ability'] == 'target'
    ];
    assert len(records) == 2;
    assert records[0]['source_ability'] == 'start';
    assert not records[0]['decision'].stable;
    assert records[1]['source_ability'] == 'intervening';
    assert records[1]['decision'].stable and records[1]['decision'].path_determined , str(
        records[1]['decision'].reasons
    );
    assert records[1]['decision'].prediction.visits[0]['target_types'] == ('DepD', );
}

test "TTG hooks: cancellation keeps path knowledge separate from reachability" {
    import from .fixtures.ttg_checkpoint_walkers { HookCancelQueue }
    with capture_dependency_checkpoints() as capture {
        observed = run_checkpoint_walk(
            HookCancelQueue(), [DepStart(value=13), DepA(), DepB()]
        );
    }
    assert observed == ['DepStart', 'DepA'];
    records = [
        r
        for r in capture.records
        if r['target_ability'] == 'target'
    ];
    assert len(records) == 1;
    decision = records[0]['decision'];
    assert decision.stable and decision.path_determined , str(decision.reasons);
    assert not decision.execution_preserved;
}

test "TTG hooks: same-line assignments have distinct source-column checkpoints" {
    import from pathlib { Path }
    import from tempfile { TemporaryDirectory }
    import from jaclang { JacRuntimeInterface as Jac }
    with TemporaryDirectory() as directory {
        source = "node HookA { has value: int = 13; }\n"
        "node HookB {}\nnode HookC {}\n"
        "walker SameLine { has mode: int = 0;\n"
        "can start with HookA entry { self.mode = 0; self.mode = here.value; visit [-->[?:HookB]]; }\n"
        "can target with HookB entry { if self.mode > 10 { visit [-->[?:HookC]]; } }\n}\n";
        Path(directory, 'auto_hook_same_line.jac').write_text(source);
        (module, ) = Jac.jac_import('auto_hook_same_line', directory);
        Path(directory, 'auto_hook_same_line.jac').unlink();
        a = module.HookA(value=13);
        a ++> module.HookB();
        with capture_dependency_checkpoints() as capture {
            run_checkpoint_walk(module.SameLine(), [a]);
        }
        assignments = [
            h
            for h in capture.hits
            if h['ability'] == 'start' and h['kind'] == 'assign'
        ];
        assert len(assignments) == 2;
        assert assignments[0]['line'] == assignments[1]['line'];
        assert assignments[0]['column'] != assignments[1]['column'];
        assert assignments[0]['point'] != assignments[1]['point'];
    }
}

test "TTG hooks: inactive capture preserves native traversal" {
    a = DepA(value=6);
    b = DepB();
    a ++> b;
    b ++> DepC();
    normal = run_checkpoint_walk(DepWalker(), [a]);
    with capture_dependency_checkpoints() as capture {
        instrumented = run_checkpoint_walk(DepWalker(), [a]);
    }
    assert normal == instrumented == ['DepA', 'DepB', 'DepC'];
    assert len(capture.records) > 0;
}

test "TTG hooks: separate implementation files receive automatic hooks" {
    import from pathlib { Path }
    import from tempfile { TemporaryDirectory }
    import from jaclang { JacRuntimeInterface as Jac }
    with TemporaryDirectory() as directory {
        Path(directory, 'auto_hook_split.jac').write_text(
            "node SplitA { has value: int = 13; }\nnode SplitB {}\nnode SplitC {}\n"
            "walker SplitWalker { has mode: int = 0;\n"
            "can start with SplitA entry; can target with SplitB entry; }\n"
        );
        Path(directory, 'auto_hook_split.impl.jac').write_text(
            "impl SplitWalker.start { self.mode = here.value; visit [-->[?:SplitB]]; }\n"
            "impl SplitWalker.target { if self.mode > 10 { visit [-->[?:SplitC]]; } }\n"
        );
        (module, ) = Jac.jac_import('auto_hook_split', directory);
        a = module.SplitA(value=13);
        b = module.SplitB();
        a ++> b;
        b ++> module.SplitC();
        with capture_dependency_checkpoints() as capture {
            observed = run_checkpoint_walk(module.SplitWalker(), [a]);
        }
        assert observed == ['SplitA', 'SplitB', 'SplitC'];
        records = [
            r
            for r in capture.records
            if r['target_ability'] == 'target'
        ];
        assert len(records) == 1;
        decision = records[0]['decision'];
        assert decision.stable and decision.path_determined , str(decision.reasons);
        assert decision.prediction.visits[0]['target_types'] == ('SplitC', );
    }
}

test "TTG hooks: inherited bodies do not apply a base-class plan to a subclass" {
    derived = type('HookDerived', (DepWalker, ), {});
    a = DepA(value=6);
    b = DepB();
    a ++> b;
    b ++> DepC();
    with capture_dependency_checkpoints() as capture {
        observed = run_checkpoint_walk(derived(), [a]);
    }
    assert observed == ['DepA', 'DepB', 'DepC'];
    assert capture.hits == [];
    assert capture.records == [];
}

test "TTG hooks: ordinary spawn syntax executes automatic checkpoints" {
    a = DepA(value=6);
    b = DepB();
    a ++> b;
    b ++> DepC();
    instance = DepWalker();
    with capture_dependency_checkpoints() as capture {
        a spawn instance;
    }
    records = [
        r
        for r in capture.records
        if r['target_ability'] == 'on_b'
    ];
    assert instance.mode == 13;
    assert len(records) == 1;
    assert records[0]['decision'].stable and records[0]['decision'].path_determined , str(
        records[0]['decision'].reasons
    );
    assert records[0]['decision'].prediction.visits[0]['target_types'] == ('DepC', );
}
