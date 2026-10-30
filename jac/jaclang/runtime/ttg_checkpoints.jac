import json;
import from hashlib { sha256 }
import from contextlib { contextmanager }
import from contextvars { ContextVar }

glob _capture: any = ContextVar('ttg_dependency_capture', `default=None);

obj CheckpointCapture {
    has records: list[dict] = [],
        graphs: dict[tuple[type, str], any] = {},
        hits: list[dict] = [],
        record_decisions: bool = True;
}

@contextmanager
def capture_dependency_checkpoints(record_decisions: bool = True) -> any {
    capture = CheckpointCapture(record_decisions=record_decisions);
    token = _capture.set(capture);
    try {
        yield capture;
    } finally {
        _capture.reset(token);
    }
}

def ttg_checkpoint(wlk: any, serialized: str, point: int, owner: type) {
    capture = _capture.get();
    if capture is None or type(wlk) is not owner {
        return;
    }
    import from jaclang.runtime.osp_kernel { _current_scope }
    import from jaclang.runtime.archetype { NodeAnchor }
    scope = _current_scope();
    if scope is None
        or scope.wlk is not wlk
        or not scope.path
        or not isinstance(scope.path[-1], NodeAnchor) {
        return;
    }
    import from jaclang.runtime.ttg_dependencies {
        decide_live_pending,
        pending_trace_queue,
        _trace_entry_handlers,
        TraceEffects
    }
    (graph, candidates) = cached_checkpoint_plan(capture, wlk, serialized);
    import from jaclang.runtime.ttg_dependency_prefetch { prefetch_continuation }
    prefetch_continuation(graph, scope, point);
    if not capture.record_decisions {
        return;
    }
    event = graph.events[point];
    queue = pending_trace_queue();
    capture.hits.append(
        {
            'walker': wlk,
            'point': point,
            'ability': event.ability,
            'line': event.line,
            'column': event.column,
            'kind': event.kind,
            'queue_types': tuple(item.node_type.__name__ for item in queue)
        }
    );
    for (index, item) in enumerate(queue) {
        handlers = _trace_entry_handlers(graph, item.node_type, TraceEffects());
        for ability in handlers {
            if ability not in candidates {
                continue;
            }
            decision = decide_live_pending(graph, point, index, ability);
            record = {
                'walker': wlk,
                'point': point,
                'source_ability': event.ability,
                'line': event.line,
                'column': event.column,
                'kind': event.kind,
                'target_index': index,
                'target_id': item.identity,
                'target_type': item.node_type.__name__,
                'target_ability': ability,
                'decision': decision
            };
            capture.records.append(record);
            record['prefetch_status'] = 'continuation';
        }
    }
}


def cached_checkpoint_plan(
    capture: CheckpointCapture, wlk: any, serialized: str
) -> tuple {
    key = (type(wlk), serialized);
    if key not in capture.graphs {
        import from jaclang.runtime.ttg_dependencies { checkpoint_graph }
        spec = json.loads(serialized);
        graph = checkpoint_graph(spec, type(wlk));
        prefix = type(wlk).__module__
            + '.'
            + type(wlk).__qualname__
            + ':'
            + sha256(serialized.encode()).hexdigest();
        setattr(graph, '_model_prefix', prefix);
        capture.graphs[key] = (graph, spec['candidates']);
    }
    return capture.graphs[key];
}
