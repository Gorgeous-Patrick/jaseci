import from contextlib { contextmanager, nullcontext }
import from contextvars { ContextVar }
import from logging { getLogger }
import from time { perf_counter }
import from threading { get_ident }
import from uuid { UUID }

glob _active: any = ContextVar('ttg_dependency_prefetch', `default=None),
     _logger = getLogger(__name__);

obj DependencyPrefetchRun {
    has ctx: any,
        max_length: int = 200,
        mode: str = 'thread',
        workers: int = 1,
        owner_thread: int = 0,
        submitted: set[UUID] = set(),
        promoted: set[UUID] = set(),
        resolved: set[tuple] = set(),
        plans: list[dict] = [],
        errors: list[str] = [];

    def summary -> dict {
        mem = self.ctx.mem;
        with mem._raw_lock {
            unused = self.submitted & set(mem.__raw_mem__);
        }
        return {
            'submitted_ids': sorted(str(uid) for uid in self.submitted),
            'promoted_ids': sorted(str(uid) for uid in self.promoted),
            'unused_cached_ids': sorted(str(uid) for uid in unused),
            'unavailable_ids': sorted(
                str(uid) for uid in (self.submitted - self.promoted - unused)
            ),
            'plans': self.plans,
            'errors': self.errors
        };
    }
}

@contextmanager
def dependency_prefetch(
    ctx: any, max_length: int = 200, mode: str = 'thread', workers: int = 1
) -> any {
    import from jaclang.runtime.ttg_checkpoints {
        _capture,
        capture_dependency_checkpoints
    }
    state = DependencyPrefetchRun(
        ctx=ctx,
        max_length=max_length,
        mode=mode,
        workers=max(1, workers),
        owner_thread=get_ident()
    );
    existing = _capture.get();
    observer = nullcontext(existing)
        if existing is not None
        else capture_dependency_checkpoints();
    with observer {
        token = _active.set(state);
        try {
            yield state;
        } finally {
            try {
                for thread in list(getattr(ctx.mem, '_prefetch_threads', [])) {
                    thread.join();
                }
            } finally {
                _active.reset(token);
            }
        }
    }
}

@contextmanager
def configured_dependency_prefetch(ctx: any, cfg: any) -> any {
    run_cfg = cfg?.run;
    if ctx is None
        or run_cfg is None
        or str(getattr(run_cfg, 'prefetching', '')).strip().lower() != 'ttg_dependency'
        or int(getattr(run_cfg, 'prefetch_limit', 0) or 0) <= 0 {
        yield None;
        return;
    }
    with dependency_prefetch(
        ctx,
        max_length=int(run_cfg.prefetch_limit),
        mode=str(getattr(run_cfg, 'async_prefetch', '')),
        workers=int(getattr(run_cfg, 'prefetch_workers', 1) or 1)
    ) as state {
        try {
            yield state;
        } finally {
            for thread in list(getattr(ctx.mem, '_prefetch_threads', [])) {
                thread.join();
            }
            setattr(ctx, '_ttg_dependency_metrics', state.summary());
        }
    }
}

def record_dependency_promotion(mem: any, uid: UUID) {
    state = _active.get();
    if state is not None
        and state.ctx.mem is mem
        and state.owner_thread == get_ident()
        and uid in state.submitted {
        state.promoted.add(uid);
    }
}

def prefetch_checkpoint(graph: any, scope: any, record: dict) {
    state = _active.get();
    if state is None {
        return;
    }
    decision = record['decision'];
    if not (
        decision.stable and decision.path_determined and decision.execution_preserved
    ) {
        record['prefetch_status'] = 'blocked';
        return;
    }
    mem = state.ctx.mem;
    if mem.store is None {
        record['prefetch_status'] = 'no_store';
        return;
    }
    record['prefetch_status'] = 'empty';
    for selected in decision.prediction.visits {
        remaining = state.max_length - len(state.submitted);
        if remaining <= 0 {
            record['prefetch_status'] = 'limit';
            return;
        }
        event = graph.events[selected['event']];
        if not event.hop_chain or event.origin not in ('here', 'root') {
            record['prefetch_status'] = 'unsupported';
            continue;
        }
        try {
            origin = state.ctx.user_root if event.origin == 'root' else None;
            origin_id = UUID(
                str(origin.id if origin is not None else record['target_id'])
            );
            origin_type = type(origin.archetype).__name__
                if origin is not None
                else record['target_type'];
        } except (ValueError, TypeError, AttributeError) {
            record['prefetch_status'] = 'transient';
            continue;
        }
        key = (id(scope), origin_id, tuple(event.hop_chain));
        if key in state.resolved {
            record['prefetch_status'] = 'deduplicated';
            continue;
        }
        started = perf_counter();
        plan: dict = {
            'origin': str(origin_id),
            'ability': record['target_ability'],
            'visit_event': event.id,
            'hops': event.hop_chain,
            'ids': [],
            'status': 'resolving'
        };
        state.plans.append(plan);
        try {
            import from jaclang.runtime.ttg_sql { compile_layered }
            import from jaclang.runtime.prefetch { dispatch_prefetch }
            with mem._raw_lock {
                cached = set(mem.__raw_mem__);
            }
            excluded = set(mem.__mem__) | cached | state.submitted | {origin_id};
            specs = [
                {
                    'idx': 0,
                    'from_type': origin_type,
                    'chain': list(event.hop_chain),
                    'is_visit': True
                }
            ];
            compiled = compile_layered(
                specs, [origin_id], list(excluded), remaining, True, False
            );
            rows = _checkpoint_rows(mem, compiled);
            ids: list[UUID] = [];
            for row in rows {
                uid = UUID(str(row[1]));
                if uid not in excluded and uid not in mem._deleted and uid not in ids {
                    ids.append(uid);
                    if len(ids) >= remaining {
                        break;
                    }
                }
            }
            plan['resolve_ms'] = (perf_counter() - started) * 1000;
            plan['ids'] = [str(uid) for uid in ids];
            state.resolved.add(key);
            if ids {
                dispatch_prefetch(
                    state.ctx, ids, state.mode, state.workers, append=True
                );
                state.submitted.update(ids);
                plan['status'] = 'submitted';
                record['prefetch_status'] = 'submitted';
            } else {
                plan['status'] = 'empty';
            }
        } except Exception as error {
            plan['status'] = 'error';
            plan['error'] = str(error);
            state.errors.append(str(error));
            record['prefetch_status'] = 'error';
            _logger.debug(f'Dependency prefetch skipped: {error}');
        }
    }
}

def _checkpoint_rows(mem: any, compiled: any) -> list {
    with mem._lock {
        mem.read_barrier();
        return mem.store.rows_in_savepoint(compiled.sql, compiled.params);
    }
}
