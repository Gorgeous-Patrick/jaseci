"""Arrival-barrier traversal for synchronous Python named-cursor walkers."""
import from types { MappingProxyType, UnionType }
import from jaclang.runtime.archetype { NodeArchetype, EdgeArchetype }
import from jaclang.runtime.graph_query { GraphQuery }
import from jaclang.runtime.osp_kernel { DEFAULT, WalkScope, scope_of }
import from jaclang.runtime.osp_kernel_sv { _mro_funcs, make_sv_runtime }

# Keep all queue mechanics, including visit insertion indices, in the old visit engine.
def visit_cursor(wlk: any, name: str, expr: any, insert_loc: int = -1) -> bool {
    scope = scope_of(wlk);
    if scope is None or scope.named_channels is None or name not in scope.named_channels {
        raise RuntimeError(f"No active named cursor {name!r} for this walker");
    }
    if isinstance(expr, EdgeArchetype)
        or (isinstance(expr, list) and any(isinstance(t, EdgeArchetype) for t in expr))
        or (isinstance(expr, GraphQuery) and expr.edges_only) {
        raise TypeError("Named cursor visits require node targets");
    }
    channel: any = scope.named_channels[name];
    DEFAULT.stack.append(channel);
    try {
        import from jaclang.runtime.runtime { JacRuntime }
        return JacRuntime.visit(wlk, expr, insert_loc);
    } finally {
        DEFAULT.stack.pop();
    }
}

def spawn_cursors(wlk: any, bindings: any) -> any {
    names: tuple[str, ...] = getattr(type(wlk), '_jac_cursor_names_', ());
    if '_jac_cursor_names_' not in type(wlk).__dict__ {
        raise TypeError("Named cursor walker inheritance is unsupported");
    }
    if not isinstance(bindings, dict) or set(bindings) != set(names) {
        raise TypeError(f"Named walker starts require exactly these cursor keys: {names!r}");
    }
    if getattr(wlk, '__jac_async__', False) {
        raise TypeError("Named cursors do not support async walkers");
    }
    if scope_of(wlk) is not None {
        raise RuntimeError("Cannot recursively spawn the same active named walker instance");
    }
    channels: dict[str, any] = {};
    for name in names {
        initial = bindings[name];
        values = [] if initial is None else (initial if isinstance(initial, list) else [initial]);
        for value in values {
            if not isinstance(value, NodeArchetype) {
                raise TypeError(f"Cursor {name!r} starts must be nodes, node lists or None");
            }
            if value.__jac__.destroyed {
                raise RuntimeError("Cannot start a cursor on a destroyed node");
            }
        }
        channels[name] = WalkScope(wlk=wlk, path=[], next=list(values), front=[], ignores=[], reports=[]);
    }
    funcs = _mro_funcs(type(wlk), '_jac_entry_funcs_');
    if _mro_funcs(type(wlk), '_jac_exit_funcs_') {
        raise TypeError("Named cursors do not support walker exit events");
    }
    for func in funcs {
        trigger = func.trigger;
        if not isinstance(trigger, dict) or set(trigger) != set(names) {
            raise TypeError("Named walker abilities must have joint entry triggers for all cursors");
        }
        for ty in trigger.values() {
            members = ty.__args__ if isinstance(ty, UnionType) else (ty,);
            if not all(isinstance(t, type) and issubclass(t, NodeArchetype) for t in members) {
                raise TypeError("Named cursor triggers must be node types");
            }
        }
    }
    scope = DEFAULT.begin(wlk, []);
    scope.named_channels = channels;
    ok = False;
    try {
        while not scope.disengaged {
            current: dict[str, any] = {};
            for name in names {
                channel: any = channels[name];
                current_node: any = None;
                while channel.front or channel.next_head < len(channel.next) {
                    if channel.front { current_node = channel.front.pop(); }
                    else {
                        current_node = channel.next[channel.next_head];
                        channel.next_head += 1;
                    }
                    if not current_node.__jac__.destroyed { break; }
                    current_node = None;
                }
                if current_node is None { break; }
                if not isinstance(current_node, NodeArchetype) {
                    raise TypeError("Named cursor visits require node targets");
                }
                current[name] = current_node;
                channel.cur_a = wlk;
                channel.cur_b = current_node;
                channel.path.append(current_node);
            }
            if len(current) != len(names) { break; }
            for current_node in current.values() {
                if _mro_funcs(type(current_node), '_jac_entry_funcs_') or _mro_funcs(type(current_node), '_jac_exit_funcs_') {
                    raise TypeError("Node event callbacks have no named cursor contract");
                }
            }
            scope.path.extend(current.values());
            positions = MappingProxyType(current);
            scope.cur_a = wlk;
            scope.cur_b = positions;
            scope.cur_entry = True;
            for func in funcs {
                trigger = func.trigger;
                if all(isinstance(current[n], trigger[n]) for n in names) {
                    func.func(wlk, positions);
                }
                if scope.disengaged { break; }
            }
        }
        ok = True;
    } finally {
        scope.named_channels = None;
        DEFAULT.finish(scope, ok, make_sv_runtime());
    }
    return wlk;
}
