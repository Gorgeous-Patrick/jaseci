"""Exercise selected-visit SQL, real background loading and cache consumption."""
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from types { SimpleNamespace }
import from threading { Event, Lock }
import from unittest.mock { patch }
import from uuid { UUID }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.runtime.context { ExecutionContext }
import from jaclang.runtime.ttg_dependency_prefetch {
    dependency_prefetch,
    DependencyPrefetchRun,
    _checkpoint_rows
}
import from jaclang.runtime.ttg_checkpoints { capture_dependency_checkpoints }
import from jaclang.runtime.prefetch { dispatch_prefetch }
import from .fixtures.ttg_prefetch_walkers {
    FetchA,
    FetchB,
    FetchC,
    FetchSubC,
    FetchD,
    FetchStop,
    FetchLink,
    FetchOther,
    FetchSubLink,
    FetchBranch,
    FetchCancelled,
    FetchMultiHop,
    FetchMultiCycle,
    FetchMultiSequence,
    FetchFilteredMultiHop,
    FetchNoise
}
import from jaclang.runtime.ttg_dependencies { analyze_walker_dependencies }

def seed_fetch_graph(project: str, value: int = 13, multihop: bool = False) -> dict {
    ctx = ExecutionContext(
        base_path_dir=project, full_target_path=str(Path(project, 'fetch.jac'))
    );
    JacRuntime.exec_ctx = ctx;
    a = FetchA(value=value);
    b = FetchB();
    root ++> a;
    a +>:FetchLink:+> b;
    c0 = FetchC(label='c0');
    c1 = FetchC(label='c1');
    c2 = FetchSubC(label='c2');
    b +>:FetchLink:+> c0;
    b +>:FetchLink:+> c1;
    b +>:FetchSubLink:+> c2;
    cs = [c0, c1, c2];
    ds = [FetchD(label='d' + str(i)) for i in range(3)];
    for d in ds {
        d +>:FetchLink:+> b;
    }
    decoy = FetchC(label='wrong-edge');
    b +>:FetchOther:+> decoy;
    mids: list[FetchNoise] = [];
    if multihop {
        mids = [FetchNoise(), FetchNoise()];
        for mid in mids {
            b +>:FetchOther:+> mid;
        }
        mids[0] +>:FetchLink:+> c0;
        mids[0] +>:FetchLink:+> c1;
        mids[1] +>:FetchLink:+> c0;
        mids[1] +>:FetchSubLink:+> c2;
    }
    a ++> FetchStop();
    ctx.mem.commit();
    result = {
        'start': a.__jac__.id,
        'c': {n.__jac__.id for n in cs},
        'd': {n.__jac__.id for n in ds},
        'decoy': decoy.__jac__.id,
        'intermediate': {n.__jac__.id for n in mids}
    };
    ctx.close();
    return result;
}

def open_fetch_context(project: str) -> ExecutionContext {
    ctx = ExecutionContext(
        base_path_dir=project, full_target_path=str(Path(project, 'fetch.jac'))
    );
    JacRuntime.exec_ctx = ctx;
    return ctx;
}

def fetch_origin(ctx: ExecutionContext, uid: any) -> FetchA {
    assert isinstance(uid, UUID);
    anchor = ctx.mem.get(uid);
    assert anchor is not None;
    arch = anchor.archetype;
    assert isinstance(arch, FetchA);
    return arch;
}

test "dependency prefetch: multi-hop path retains types directions and terminal dispatch" {
    graph = analyze_walker_dependencies(FetchMultiHop);
    visits = [
        e
        for e in graph.events
        if e.ability == 'choose' and e.kind == 'visit'
    ];
    assert len(visits) == 1;
    assert visits[0].hop_chain
        == (('FetchOther', 'FetchNoise', 2), ('FetchLink', 'FetchC', 2)) , str(
        visits[0].hop_chain
    );
    assert visits[0].targets == ('FetchC', );
    assert graph.dispatch[visits[0].id] == ['collect'];
    assert graph.predict_handler('choose', {}).complete;
    mixed = analyze_walker_dependencies(FetchMultiSequence).predict_handler(
        'choose', {}
    );
    assert mixed.complete , str(mixed.unresolved);
    assert len(mixed.visits) == 2;
    cycle = analyze_walker_dependencies(FetchMultiCycle);
    event = [
        e
        for e in cycle.events
        if e.ability == 'choose' and e.kind == 'visit'
    ][0];
    assert event.hop_chain
        == (
            ('FetchOther', 'FetchNoise', 2),
            ('FetchOther', 'FetchB', 1),
            ('FetchLink', 'FetchC', 2)
        ) , str(event.hop_chain);
}

test "dependency prefetch: multi-hop value filters remain explicit barriers" {
    graph = analyze_walker_dependencies(FetchFilteredMultiHop);
    assert not graph.predict_handler('choose', {}).complete;
    assert any(
        e.kind == 'barrier'
        for e in graph.events
        if e.ability == 'choose'
    );
}

def run_multi_walk(origin: FetchA, cyclic: bool) -> list[str] {
    if cyclic {
        cycle = FetchMultiCycle();
        origin spawn cycle;
        return cycle.seen;
    }
    direct = FetchMultiHop();
    origin spawn direct;
    assert direct.intermediate_visits == 0;
    return direct.seen;
}

test "dependency prefetch: multi-hop and finite cyclic paths consume terminal payloads in native order" {
    original = JacRuntime.exec_ctx;
    try {
        for cyclic in [False, True] {
            for mode in ['', 'thread'] {
                with TemporaryDirectory() as project {
                    ids = seed_fetch_graph(project, multihop=True);
                    ctx = open_fetch_context(project);
                    try {
                        expected = run_multi_walk(
                            fetch_origin(ctx, ids['start']), cyclic
                        );
                        assert set(expected) == {'c0', 'c1', 'c2'} , str(expected);
                    } finally {
                        ctx.close();
                    }
                    ctx = open_fetch_context(project);
                    try {
                        origin = fetch_origin(ctx, ids['start']);
                        with capture_dependency_checkpoints() as capture {
                            with dependency_prefetch(ctx, mode=mode) as run {
                                seen = run_multi_walk(origin, cyclic);
                            }
                        }
                        assert run.errors == [] , str(run.errors);
                        assert seen == expected , str(seen);
                        assert run.submitted == ids['c'] , str(run.summary());
                        assert run.promoted == ids['c'] , str(run.summary());
                        assert not (run.submitted & ids['intermediate']);
                        assert ids['decoy'] not in run.submitted;
                        assert any(
                            r.get('prefetch_status') == 'submitted'
                            for r in capture.records
                        ) , str(capture.records);
                    } finally {
                        ctx.close();
                    }
                }
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: chosen branch and edge subtypes populate and consume raw cache" {
    original = JacRuntime.exec_ctx;
    try {
        for (value, chosen, mode) in [(13, 'c', ''), (3, 'd', 'thread')] {
            with TemporaryDirectory() as project {
                ids = seed_fetch_graph(project, value);
                ctx = open_fetch_context(project);
                try {
                    origin = fetch_origin(ctx, ids['start']);
                    wlk = FetchBranch();
                    with capture_dependency_checkpoints() as capture {
                        with dependency_prefetch(ctx, mode=mode) as run {
                            origin spawn wlk;
                        }
                    }
                    assert run.errors == [] , str(run.errors);
                    assert run.submitted == ids[chosen] , str(run.summary());
                    assert run.promoted == ids[chosen] , str(run.summary());
                    assert sorted(wlk.seen) == [chosen + str(i) for i in range(3)];
                    assert ids['decoy'] not in run.submitted;
                    assert len(run.plans) == 1 , str(run.plans);
                    assert run.summary()['unused_cached_ids'] == [];
                    assert run.summary()['unavailable_ids'] == [];
                    statuses = [
                        r.get('prefetch_status')
                        for r in capture.records
                        if r['target_ability'] == 'choose'
                    ];
                    assert statuses == ['submitted', 'deduplicated'] , str(statuses);
                } finally {
                    ctx.close();
                }
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: configured policy activates with ordinary spawn" {
    import jaclang.project.config as config;
    from_cfg = config.get_config();
    assert from_cfg is not None;
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                with patch.object(from_cfg.run, 'prefetching', 'ttg_dependency'), patch.object(
                    from_cfg.run, 'async_prefetch', 'thread'
                ) {
                    origin spawn FetchBranch();
                }
                metrics = getattr(ctx, '_ttg_dependency_metrics');
                assert set(metrics['submitted_ids'])
                    == {str(uid) for uid in ids['c']} , str(metrics);
                assert set(metrics['promoted_ids']) == set(metrics['submitted_ids']) , str(
                    metrics
                );
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: cap preserves demand results and skips unselected branch" {
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                wlk = FetchBranch();
                with dependency_prefetch(ctx, max_length=2, mode='') as run {
                    origin spawn wlk;
                }
                assert len(run.submitted) == 2;
                assert run.submitted <= ids['c'];
                assert run.promoted == run.submitted;
                assert sorted(wlk.seen) == ['c0', 'c1', 'c2'];
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: cancelled queued target submits no work" {
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                model = TestAdmissionModel(reject_phase='never');
                with dependency_prefetch(ctx, mode='', model=model) as run {
                    origin spawn FetchCancelled();
                }
                assert run.submitted == set();
                assert run.plans == [];
                assert run.errors == [];
                assert model.calls == [];
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: speculative SQL error rolls back its savepoint only" {
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ctx = open_fetch_context(project);
            try {
                store = ctx.mem.store;
                assert store is not None;
                store.rows('CREATE TABLE dependency_savepoint_test (n integer)', {});
                ctx.mem.read_barrier();
                store.rows('INSERT INTO dependency_savepoint_test VALUES (7)', {});
                raised = False;
                try {
                    _checkpoint_rows(
                        ctx.mem, SimpleNamespace(sql='SELECT 1 / 0', params={})
                    );
                } except Exception {
                    raised = True;
                }
                assert raised;
                assert store.rows('SELECT n FROM dependency_savepoint_test', {})[0][0]
                    == 7;
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: resolver error falls back to correct foreground traversal" {
    import jaclang.runtime.ttg_sql as sql;
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                wlk = FetchBranch();
                with patch.object(
                    sql,
                    'compile_layered',
                    return_value=SimpleNamespace(sql='SELECT 1 / 0', params={})
                ) {
                    with dependency_prefetch(ctx) as run {
                        origin spawn wlk;
                    }
                }
                assert run.submitted == set();
                assert run.errors;
                assert sorted(wlk.seen) == ['c0', 'c1', 'c2'];
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: appending batches retains every outstanding worker" {
    first = Event();
    second = Event();
    entered = [Event(), Event()];
    gates = [first, second];
    ids = [UUID(int=1), UUID(int=2)];
    loaded: list = [];
    def load(batch: list) {
        index = 0 if batch[0] == ids[0] else 1;
        entered[index].set();
        assert gates[index].`wait(timeout=5);
        loaded.extend(batch);
    }
    mem = SimpleNamespace(prefetch=load);
    ctx = SimpleNamespace(mem=mem);
    try {
        dispatch_prefetch(ctx, [ids[0]], 'thread', append=True);
        assert entered[0].`wait(timeout=5);
        dispatch_prefetch(ctx, [ids[1]], 'thread', append=True);
        assert entered[1].`wait(timeout=5);
        assert mem._prefetch_ids == set(ids);
        assert len(mem._prefetch_threads) == 2;
        second.set();
        mem._prefetch_threads[1].join(timeout=5);
        assert not mem._prefetch_done.is_set();
        first.set();
        assert mem._prefetch_done.`wait(timeout=5);
        assert set(loaded) == set(ids);
    } finally {
        first.set();
        second.set();
        for thread in getattr(mem, '_prefetch_threads', []) {
            thread.join(timeout=5);
        }
    }
}

test "dependency prefetch: worker failure preserves foreground demand results" {
    import from jaclang.server.session { Session }
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                wlk = FetchBranch();
                with patch.object(
                    Session, 'prefetch', side_effect=RuntimeError('worker failed')
                ) {
                    with dependency_prefetch(ctx, mode='thread') as run {
                        origin spawn wlk;
                    }
                }
                assert run.submitted == ids['c'];
                assert run.promoted == set();
                assert set(run.summary()['unavailable_ids'])
                    == {str(uid) for uid in ids['c']};
                assert sorted(wlk.seen) == ['c0', 'c1', 'c2'];
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: two selected visit sites load both batches into the same cache" {
    import from .fixtures.ttg_prefetch_walkers { FetchBoth }
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                wlk = FetchBoth();
                with dependency_prefetch(ctx, mode='thread') as run {
                    origin spawn wlk;
                }
                assert run.errors == [] , str(run.errors);
                assert run.submitted == ids['c'] | ids['d'] , str(run.summary());
                assert run.promoted == run.submitted , str(run.summary());
                assert sorted(wlk.seen) == ['c0', 'c1', 'c2', 'd0', 'd1', 'd2'];
                assert len(run.plans) == 2;
                assert run.summary()['unused_cached_ids'] == [];
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

import from jaclang.runtime.ttg_prefetch_model {
    PrefetchDecisionModel,
    PrefetchFeatures,
    PrefetchAdmission,
    PrefetchOutcome
}

obj TestAdmissionModel(PrefetchDecisionModel) {
    has reject_phase: str = 'resolve',
        calls: list[str] = [];

    def decide(features: PrefetchFeatures) -> PrefetchAdmission {
        import from jaclang.runtime.ttg_prefetch_model { PrefetchAdmission }
        self.calls.append(features.phase);
        if self.reject_phase == 'error' {
            raise ValueError('model failure');
        }
        return PrefetchAdmission(features.phase != self.reject_phase, 'test admission');
    }

    def observe(outcome: PrefetchOutcome) { }
}

test "dependency prefetch: replaceable model skips resolution or payload with identical results" {
    import from jaclang.runtime.ttg_prefetch_profile { OnlinePrefetchProfile }
    original = JacRuntime.exec_ctx;
    try {
        for phase in ['resolve', 'load', 'error'] {
            with TemporaryDirectory() as project {
                ids = seed_fetch_graph(project);
                ctx = open_fetch_context(project);
                try {
                    origin = fetch_origin(ctx, ids['start']);
                    wlk = FetchBranch();
                    model = TestAdmissionModel(reject_phase=phase);
                    with patch(
                        'jaclang.runtime.ttg_dependency_prefetch._checkpoint_rows',
                        wraps=_checkpoint_rows
                    ) as rows {
                        with dependency_prefetch(
                            ctx, model=model, provider=OnlinePrefetchProfile()
                        ) as run {
                            origin spawn wlk;
                        }
                        assert rows.call_count == (1 if phase == 'load' else 0);
                    }
                    assert sorted(wlk.seen) == ['c0', 'c1', 'c2'];
                    assert run.submitted == set();
                    assert len(run.plans) == 1;
                    assert run.feedback[0]['demanded'] , str(run.summary());
                    assert model.calls
                        == (['resolve', 'load'] if phase == 'load' else ['resolve']);
                    assert bool(run.errors) == (phase == 'error');
                } finally {
                    ctx.close();
                }
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: live profile observes actual branches and payload readiness" {
    import from jaclang.runtime.ttg_prefetch_profile { OnlinePrefetchProfile }
    original = JacRuntime.exec_ctx;
    profile = OnlinePrefetchProfile();
    outcomes: list = [];
    try {
        for value in [13, 3] {
            with TemporaryDirectory() as project {
                ids = seed_fetch_graph(project, value);
                ctx = open_fetch_context(project);
                try {
                    origin = fetch_origin(ctx, ids['start']);
                    with dependency_prefetch(ctx, provider=profile) as run {
                        origin spawn FetchBranch();
                    }
                    assert run.errors == [] , str(run.errors);
                    assert len(run.feedback) == 1 , str(run.summary());
                    current_run = run as DependencyPrefetchRun;
                    metrics = current_run.summary();
                    outcome: dict = metrics['feedback'][0];
                    assert outcome['demanded'] , str(outcome);
                    assert outcome['payload_ms'] is not None;
                    assert outcome['overlap_ms'] >= 0;
                    assert outcome['resolved_nodes'] == 3;
                    outcomes.append(outcome);
                } finally {
                    ctx.close();
                }
            }
        }
        assert outcomes[0]['ability_key'] == outcomes[1]['ability_key'];
        branch = profile.branches[outcomes[0]['ability_key']];
        assert branch['entries'] == 2 , str(branch);
        for outcome in outcomes {
            assert branch['visits'][outcome['site_key']] == 1 , str(branch);
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}

test "dependency prefetch: configured model and scoped override select policy" {
    import jaclang.project.config as config;
    import from jaclang.runtime.ttg_prefetch_model {
        use_prefetch_model,
        AlwaysPrefetch
    }
    cfg = config.get_config();
    assert cfg is not None;
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            for use_override in [False, True] {
                ctx = open_fetch_context(project);
                try {
                    origin = fetch_origin(ctx, ids['start']);
                    wlk = FetchBranch();
                    with patch.object(cfg.run, 'prefetching', 'ttg_dependency'), patch.object(
                        cfg.run, 'async_prefetch', ''
                    ), patch.object(
                        cfg.run, 'ttg_prefetch_model', 'expected_benefit'
                    ) {
                        if use_override {
                            with use_prefetch_model(AlwaysPrefetch()) {
                                origin spawn wlk;
                            }
                        } else {
                            origin spawn wlk;
                        }
                    }
                    metrics: dict = getattr(ctx, '_ttg_dependency_metrics');
                    assert len(metrics['submitted_ids'])
                        == (3 if use_override else 0) , str(metrics);
                    assert metrics['model']
                        == ('AlwaysPrefetch' if use_override else 'ExpectedBenefit');
                    assert len(metrics['feedback']) == 1 , str(metrics);
                    assert sorted(wlk.seen) == ['c0', 'c1', 'c2'];
                } finally {
                    ctx.close();
                }
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}
