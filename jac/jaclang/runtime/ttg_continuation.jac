"""Execute a bounded abstract continuation in the walker's FIFO entry order.

The resolver returns ordered, concrete node identities and runtime types. It
does not execute abilities. Unknown effects stop the proven prefix; payload
deduplication never deduplicates executions or walker state transitions.
"""
import from jaclang.runtime.ttg_dependencies {
    _trace_snapshot,
    _trace_eval,
    _trace_entry_handlers,
    _trace_node_effects,
    _trace_field_effects,
    TraceEffects
}
import ast as pyast;
import from dataclasses { fields }
import from jaclang.runtime.archetype { NodeArchetype }
import sys;

def continuation_type(wlk: any, name: str, module_name: str = '') -> any {
    import from jaclang.runtime.runtime { JacRuntime }
    scope_name = module_name or type(wlk).__module__;
    module = JacRuntime.loaded_modules.get(scope_name) or sys.modules.get(scope_name);
    if module is None {
        return None;
    }
    direct = vars(module).get(name);
    if isinstance(direct, type) {
        return direct;
    }
    matches = {
        value
        for value in vars(module).values()
        if isinstance(value, type)
            and value.__name__ == name
            and (not module_name or value.__module__ == module_name)
    };
    return next(iter(matches)) if len(matches) == 1 else None;
}

def _append_argument_known(event: any, values: dict, node_type: type) -> bool {
    try {
        _trace_eval(event.expression, values, event.ability);
        return True;
    } except KeyError {
        if node_type.__getattribute__ is not NodeArchetype.__getattribute__ {
            return False;
        }
        tree: any = pyast.parse(event.expression, mode='eval').body;
        if not isinstance(tree, pyast.Attribute)
            or not isinstance(tree.value, pyast.Name)
            or tree.value.id != 'here' {
            return False;
        }
        declared = {field.name for field in fields(node_type)};
        if tree.attr not in declared {
            return False;
        }
        return not any(
            isinstance(vars(base).get(tree.attr), property)
            for base in node_type.__mro__
        );
    }
}

def _finish_entry_prefix(result: dict, graph: any, node_types: list) -> dict {
    if getattr(graph.runtime_walker, '_jac_exit_funcs_', [])
        or any(
            getattr(node_type, '_jac_exit_funcs_', []) for node_type in node_types
        ) {
        result['stop'] = 'Exit callbacks require a later continuation';
    } else {
        result['complete'] = True;
    }
    return result;
}

def plan_continuation(
    graph: any,
    current: dict,
    point: int,
    snapshot: dict,
    pending: list[dict],
    resolve: any,
    max_nodes: int = 200,
    max_steps: int = 2000
) -> dict {
    result: dict = {
        'nodes': [],
        'paths': [],
        'branches': [],
        'stop': '',
        'complete': False,
        'steps': 0,
        'executions': []
    };
    values = _trace_snapshot(snapshot);
    effects = TraceEffects();
    _trace_field_effects(
        graph,
        set(values)
            | {
                e.writes
                for e in graph.events
                if e.writes
            },
        effects
    );
    if effects.unknown {
        result['stop'] = 'Walker field access has unknown effects';
        return result;
    }
    queue = list(pending);
    exit_types = list(current.get('ancestor_types', [current['node_type']]));
    head = 0;
    active = current;
    event = graph.events[point];
    handlers = _trace_entry_handlers(graph, active['node_type'], effects);
    if effects.unknown or event.ability not in handlers {
        result['stop'] = 'Current entry dispatch is unresolved';
        return result;
    }
    handler_index = handlers.index(event.ability);
    cursor = event.next_id;
    while result['steps'] < max_steps {
        result['steps'] += 1;
        if cursor == -1 {
            handler_index += 1;
            if handler_index < len(handlers) {
                ability = handlers[handler_index];
                values = {
                    k: v
                    for (k, v) in values.items()
                    if k.startswith('self.')
                };
                cursor = graph.entries[ability];
                continue;
            }
            effects = TraceEffects();
            _trace_node_effects(graph, active['node_type'], effects);
            if effects.unknown {
                result['stop'] = 'Node entry handler has unknown effects';
                return result;
            }
            if head >= len(queue) {
                return _finish_entry_prefix(result, graph, exit_types);
            }
            if len(result['nodes']) >= max_nodes {
                result['stop'] = 'Node execution budget exhausted';
                return result;
            }
            while head < len(queue) and 'deferred_event' in queue[head] {
                if result['steps'] >= max_steps {
                    result['stop'] = 'Abstract execution step budget exhausted';
                    return result;
                }
                result['steps'] += 1;
                deferred = queue[head];
                head += 1;
                visit_event = deferred['deferred_event'];
                targets = resolve(deferred['origin'], visit_event);
                if targets is None {
                    result['stop'] = 'Path resolution declined';
                    return result;
                }
                result['paths'].append(
                    {
                        'event': visit_event.id,
                        'origin': str(deferred['origin']['id']),
                        'origin_kind': visit_event.origin,
                        'targets': [str(item['id']) for item in targets]
                    }
                );
                queue[head:head] = targets;
            }
            if head >= len(queue) {
                return _finish_entry_prefix(result, graph, exit_types);
            }
            active = queue[head];
            exit_types.append(active['node_type']);
            head += 1;
            result['nodes'].append(active);
            result['executions'].append(str(active['id']));
            effects = TraceEffects();
            handlers = _trace_entry_handlers(graph, active['node_type'], effects);
            if effects.unknown {
                result['stop'] = 'Future entry dispatch is unresolved';
                return result;
            }
            values = {
                k: v
                for (k, v) in values.items()
                if k.startswith('self.')
            };
            handler_index = -1;
            continue;
        }
        event = graph.events[cursor];
        try {
            if event.kind in ('barrier', 'cancel') {
                result['stop'] = event.kind
                    + ' at '
                    + event.ability
                    + ':'
                    + str(event.line);
                return result;
            }
            if event.kind == 'assign' {
                values[event.writes] = _trace_eval(
                    event.expression, values, event.ability
                );
                values.pop(event.writes + '::list', None);
            } elif event.kind == 'append' {
                if not values.get(event.writes + '::list', False)
                    or not _append_argument_known(event, values, active['node_type']) {
                    result['stop'] = 'List append receiver or argument is unresolved';
                    return result;
                }
                values.pop(event.writes, None);
            } elif event.kind == 'branch' {
                choice = bool(_trace_eval(event.expression, values, event.ability));
                result['branches'].append({'event': event.id, 'taken': choice});
                cursor = event.true_id if choice else event.false_id;
                continue;
            } elif event.kind == 'visit' {
                if not event.hop_chain or event.origin not in ('here', 'root') {
                    result['stop'] = 'Visit origin or path is unresolved';
                    return result;
                }
                # Pure supported continuations preserve topology. Delay SQL until
                # all preceding entry code is proven, including possible cancel.
                queue.append({'deferred_event': event, 'origin': active});
            }
        } except (KeyError, ValueError, TypeError, ArithmeticError) as error {
            result['stop'] = 'Unknown scalar fact: ' + str(error);
            return result;
        }
        cursor = event.next_id;
    }
    result['stop'] = 'Abstract execution step budget exhausted';
    return result;
}
