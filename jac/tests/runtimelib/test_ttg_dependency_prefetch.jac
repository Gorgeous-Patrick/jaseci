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
    FetchCancelled
}

def seed_fetch_graph(project: str, value: int = 13) -> dict {
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
    a ++> FetchStop();
    ctx.mem.commit();
    result = {
        'start': a.__jac__.id,
        'c': {n.__jac__.id for n in cs},
        'd': {n.__jac__.id for n in ds},
        'decoy': decoy.__jac__.id
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
                with dependency_prefetch(ctx, mode='') as run {
                    origin spawn FetchCancelled();
                }
                assert run.submitted == set();
                assert run.plans == [];
                assert run.errors == [];
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
