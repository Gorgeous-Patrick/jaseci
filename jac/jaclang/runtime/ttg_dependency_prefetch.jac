import from contextlib { contextmanager, nullcontext }
import from contextvars { ContextVar }
import from logging { getLogger }
import from time { perf_counter }
import from threading { get_ident }
import from uuid { UUID }
import from jaclang.runtime.ttg_prefetch_model {
    PrefetchDecisionModel,
    PrefetchFeatures,
    PrefetchAdmission,
    PrefetchOutcome,
    create_prefetch_model,
    _model_override
}
import from jaclang.runtime.ttg_prefetch_profile {
    PrefetchFeatureProvider,
    default_prefetch_profile
}

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
        errors: list[str] = [],
        model: PrefetchDecisionModel | None = None,
        provider: PrefetchFeatureProvider | None = None,
        considered: dict[tuple, dict] = {},
        feedback: list[dict] = [];

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
            'errors': self.errors,
            'model': type(self.model).__name__,
            'feature_provider': type(self.provider).__name__,
            'feedback': self.feedback
        };
    }
}

@contextmanager
def dependency_prefetch(
    ctx: any,
    max_length: int = 200,
    mode: str = 'thread',
    workers: int = 1,
    model: PrefetchDecisionModel | None = None,
    provider: PrefetchFeatureProvider | None = None
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
        owner_thread=get_ident(),
        model=model or _model_override.get() or create_prefetch_model('always'),
        provider=provider or default_prefetch_profile
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
                finish_prefetch_feedback(state);
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
        workers=int(getattr(run_cfg, 'prefetch_workers', 1) or 1),
        model=_model_override.get()
            or create_prefetch_model(
                str(getattr(run_cfg, 'ttg_prefetch_model', 'always'))
            )
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
        if key in state.considered {
            record['prefetch_status'] = 'deduplicated';
            continue;
        }
        plan: dict = {
            'origin': str(origin_id),
            'ability': record['target_ability'],
            'visit_event': event.id,
            'hops': event.hop_chain,
            'ids': [],
            'status': 'considering',
            'candidate_at': perf_counter(),
            'queue_position': record['target_index'],
            'site_key': model_site_key(state, graph, event.id),
            'ability_key': model_ability_key(state, graph, event.ability),
            'decisions': [],
            'demanded': False,
            'decision_ms': 0.0
        };
        state.plans.append(plan);
        state.considered[key] = plan;
        first_admission = admit_prefetch(state, plan, 'resolve', remaining);
        if not first_admission.admit {
            plan['status'] = 'model_skipped';
            record['prefetch_status'] = 'model_skipped';
            continue;
        }
        try {
            started = perf_counter();
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
            plan['resolved_nodes'] = len(ids);
            state.resolved.add(key);
            if ids {
                second_admission = admit_prefetch(
                    state, plan, 'load', remaining, first_admission.probe
                );
                if not second_admission.admit {
                    plan['status'] = 'model_skipped_load';
                    record['prefetch_status'] = 'model_skipped_load';
                    continue;
                }
                plan['dispatch_at'] = perf_counter();
                observer = payload_observer(state, plan);
                dispatch_prefetch(
                    state.ctx,
                    ids,
                    state.mode,
                    state.workers,
                    append=True,
                    observer=observer
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


def model_ability_key(state: any, graph: any, ability: str) -> str {
    return str(getattr(graph, '_model_prefix', graph.walker_name))
        + ':'
        + ability
        + ':'
        + str(state.mode or 'sync')
        + ':'
        + str(state.workers);
}

def model_site_key(state: any, graph: any, point: int) -> str {
    return model_ability_key(state, graph, graph.events[point].ability)
        + ':'
        + str(point);
}

def admit_prefetch(
    state: any, plan: dict, phase: str, remaining: int, probe: bool = False
) -> PrefetchAdmission {
    started = perf_counter();
    inputs: dict = {};
    try {
        context = PrefetchFeatures(
            site_key=plan['site_key'],
            ability_key=plan['ability_key'],
            phase=phase,
            queue_position=plan['queue_position'],
            remaining_budget=remaining,
            mode=state.mode,
            resolved_nodes=plan.get('resolved_nodes'),
            probe=probe
        );
        features = state.provider.estimate(context);
        inputs = features.to_dict();
        admission = state.model.decide(features);
        if not isinstance(admission, PrefetchAdmission)
            or type(admission.admit) is not bool {
            raise TypeError(
                'Decision model must return PrefetchAdmission with a boolean admit field'
            );
        }
        result = admission;
    } except Exception as error {
        state.errors.append('Decision model: ' + str(error));
        result = PrefetchAdmission(
            False, 'model or feature-provider error: ' + str(error)
        );
    }
    elapsed = (perf_counter() - started) * 1000;
    plan['decision_ms'] += elapsed;
    plan['decisions'].append(
        {
            'model': type(state.model).__name__,
            'inputs': inputs,
            'output': result.to_dict(),
            'elapsed_ms': elapsed
        }
    );
    return result;
}

def payload_observer(state: any, plan: dict) -> any {
    def completed(ids: list, elapsed_ms: float, error: str | None) {
        ready_ms = (perf_counter() - plan['dispatch_at']) * 1000;
        plan['payload_ms'] = max(float(plan.get('payload_ms', 0.0)), ready_ms);
        if error is not None {
            plan['payload_error'] = error;
        }
    }
    return completed;
}

def record_model_event(wlk: any, serialized: str, point: int, owner: type) {
    state = _active.get();
    if state is None or type(wlk) is not owner or state.owner_thread != get_ident() {
        return;
    }
    import from jaclang.runtime.osp_kernel { _current_scope }
    import from jaclang.runtime.archetype { NodeAnchor }
    import from jaclang.runtime.ttg_checkpoints { _capture, cached_checkpoint_plan }
    scope = _current_scope();
    capture = _capture.get();
    if scope is None
        or capture is None
        or scope.wlk is not wlk
        or not scope.path
        or not isinstance(scope.path[-1], NodeAnchor) {
        return;
    }
    (graph, candidates) = cached_checkpoint_plan(capture, wlk, serialized);
    event = graph.events[point];
    ability_key = model_ability_key(state, graph, event.ability);
    try {
        if event.kind == 'entry' {
            state.provider.record_entry(ability_key);
        } elif event.kind == 'visit' {
            site_key = model_site_key(state, graph, point);
            state.provider.record_visit(ability_key, site_key);
            origin = state.ctx.user_root if event.origin == 'root' else scope.path[-1];
            if origin.id is None {
                return;
            }
            key = (id(scope), origin.id, tuple(event.hop_chain));
            plan = state.considered.get(key);
            if plan is not None and not plan['demanded'] {
                plan['demanded'] = True;
                plan['demand_at'] = perf_counter();
            }
        }
    } except Exception as error {
        state.errors.append('Model observation: ' + str(error));
    }
}

def finish_prefetch_feedback(state: any) {
    for plan in state.plans {
        demand_at = plan.get('demand_at');
        overlap: float | None = None;
        if demand_at is not None {
            if 'dispatch_at' in plan {
                anchor = plan['dispatch_at'];
            } else {
                anchor = plan['candidate_at']
                    + (plan.get('resolve_ms', 0.0) + plan['decision_ms']) / 1000;
            }
            overlap = max(0.0, (demand_at - anchor) * 1000);
        }
        outcome = PrefetchOutcome(
            site_key=plan['site_key'],
            ability_key=plan['ability_key'],
            demanded=plan['demanded'],
            resolution_ms=plan.get('resolve_ms'),
            payload_ms=plan.get('payload_ms') if 'payload_error' not in plan else None,
            overlap_ms=overlap,
            resolved_nodes=plan.get('resolved_nodes')
        );
        state.feedback.append(outcome.to_dict());
        for observer in [state.provider, state.model] {
            try {
                observer.observe(outcome);
            } except Exception as error {
                state.errors.append('Model feedback: ' + str(error));
            }
        }
    }
}
