"""Implementation for TTG Generator constructs."""

import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.archetype { NodeAnchor, VisitType }
import from jaclang.jac0core.constant { Tokens as Tok }
import from jaclang.runtimelib.topology_index { TopologyIndex }
import from uuid { UUID }

"""Return a support root anchor without emitting a tier-hit access row.

TTG needs foreign roots only to read their topology index. That lookup is
planning work, not a walker demand access. The elapsed time remains part of
TTG plan time, while access-log hit-rate rows stay limited to application
reads and the dispatched prefetch results.
"""
@classmethod
impl JacTTGGenerator._get_support_root_anchor(
    cls: type[JacTTGGenerator], mem: any, id: UUID
) -> (NodeAnchor | None) {
    anchor = None;
    try {
        l1 = mem?.__mem__;
        if isinstance(l1, dict) {
            anchor = l1.get(id);
        }
    } except Exception {
        ;
    }
    if anchor is None {
        try {
            anchor = mem.promote_raw(id);
        } except Exception {
            ;
        }
    }
    if isinstance(anchor, NodeAnchor) {
        return anchor;
    }
    return None;
}

"""Resolve a VisitType field (type or string name) to a type name string."""
@classmethod
impl JacTTGGenerator._resolve_type_name(
    cls: type[JacTTGGenerator], ref: (type | str | None)
) -> (str | None) {
    if ref is None {
        return None;
    }
    if isinstance(ref, str) {
        return ref;
    }
    return ref.__name__;
}

"""Find the AST Archetype node for a walker class.

Looks up the AST Module from the program hub first. On a hub miss,
deserializes the module's JIR cache via JirReader and stores the result
in the hub so subsequent calls are free.
"""
@classmethod
impl JacTTGGenerator._find_walker_ast_node(
    cls: type[JacTTGGenerator], warch_cls: type
) -> (uni.Archetype | None) {
    import from jaclang.jac0core.runtime { JacRuntime }
    program = JacRuntime.get_program();
    module_name = warch_cls.__module__;
    class_name = warch_cls.__name__;
    # Get the Python module to find its file path.
    py_module = JacRuntime.loaded_modules.get(module_name);
    if py_module is None {
        import sys;
        py_module = sys.modules.get(module_name);
    }
    if py_module is None {
        return None;
    }
    file_path = py_module?.__file__;
    if file_path is None {
        return None;
    }
    # Look up the AST Module from the program hub.
    ast_module = program.mod.hub.get(file_path);
    if ast_module is None {
        # Hub miss — deserialize from JIR cache.
        try {
            import from jaclang.jac0core.jir {
                get_module_cache_path,
                is_module_cache_valid
            }
            import from jaclang.jac0core.jir_passes { JirReader }
            cache_path = get_module_cache_path(file_path);
            if is_module_cache_valid(file_path, cache_path) {
                reader = JirReader(_source_path=file_path);
                ast_module = reader.read_module(cache_path.read_bytes());
                if ast_module is not None {
                    program.mod.hub[file_path] = ast_module;
                }
            }
        } except Exception {
            ;
        }
    }
    if ast_module is None {
        return None;
    }
    # Search for the walker archetype in this module.
    for arch in ast_module.get_all_sub_nodes(uni.Archetype) {
        if (arch.arch_type.name == Tok.KW_WALKER and arch.name.value == class_name) {
            return arch;
        }
    }
    return None;
}

"""Resolve a name to an Archetype AST node via symbol table lookup."""
@classmethod
impl JacTTGGenerator._resolve_archetype(
    cls: type[JacTTGGenerator], scope_src: any, name: str
) -> (uni.Archetype | None) {
    import from typing { cast }
    scope = scope_src.find_parent_of_type(uni.UniScopeNode);
    if scope is None {
        return None;
    }
    result = scope.lookup(name);
    if result is None {
        return None;
    }
    return cast(uni.Archetype | None, result.decl.find_parent_of_type(uni.Archetype));
}

"""Extract edge type and optional node filter from an EdgeOpRef or FilterCompr."""
@classmethod
impl JacTTGGenerator._extract_edge_step(
    cls: type[JacTTGGenerator], scope: any, item: any
) -> tuple[str | None, str | None, int] {
    edge_type_name: (str | None) = None;
    node_filter_name: (str | None) = None;
    direction = 2;  # Default: outgoing
    # Check if this is an EdgeOpRef
    if isinstance(item, uni.EdgeOpRef) {
        fc = item?.filter_cond;
        if fc is not None {
            # Extract edge type from f_type
            ft = fc?.f_type;
            if ft is not None {
                # Check if f_type is already a Name/Token directly
                type_name: (str | None) = None;
                if isinstance(ft, uni.Name) {
                    type_name = ft.value;
                } else {
                    # Search for Name sub_nodes
                    names = ft.get_all_sub_nodes(uni.Name);
                    if (len(names) > 0) {
                        type_name = names[0].value;
                    }
                }
                if type_name is not None {
                    edge_arch = cls._resolve_archetype(scope, type_name);
                    if edge_arch is not None {
                        edge_type_name = edge_arch.name.value;
                    }
                }
            }
        }
        # Extract direction
        edge_dir = item?.edge_dir;
        if edge_dir is not None {
            dir_name = getattr(edge_dir, 'name', '');
            if 'IN' in str(dir_name) {
                direction = 1;
            } elif 'OUT' in str(dir_name) {
                direction = 2;
            } else {
                direction = 3;  # Both
            }
        }
    } elif isinstance(item, uni.FilterCompr) {
        # This is a node filter like [?:Profile]
        ft = item?.f_type;
        if ft is not None {
            # Check if f_type is already a Name/Token directly
            type_name: (str | None) = None;
            if isinstance(ft, uni.Name) {
                type_name = ft.value;
            } else {
                names = ft.get_all_sub_nodes(uni.Name);
                if (len(names) > 0) {
                    type_name = names[0].value;
                }
            }
            if type_name is not None {
                node_arch = cls._resolve_archetype(scope, type_name);
                if node_arch is not None {
                    node_filter_name = node_arch.name.value;
                }
            }
        }
    }
    return (edge_type_name, node_filter_name, direction);
}

"""Collect sub-nodes of `node_type` from an Ability, following the link
to its separately-defined `impl` body."""
@classmethod
impl JacTTGGenerator._ability_sub_nodes(
    cls: type[JacTTGGenerator], ability: uni.Ability, node_type: type
) -> list {
    result = ability.get_all_sub_nodes(node_type);
    body = ability?.body;
    if isinstance(body, uni.ImplDef) {
        result.extend(body.get_all_sub_nodes(node_type));
    }
    return result;
}

"""Extract a type name string from an AST type annotation expression."""
@classmethod
impl JacTTGGenerator._ast_type_name(
    cls: type[JacTTGGenerator], expr: (uni.UniNode | None)
) -> (str | None) {
    if expr is None {
        return None;
    }
    if isinstance(expr, uni.Name) {
        return expr.value;
    }
    if isinstance(expr, uni.Token) {
        return expr.value;
    }
    if isinstance(expr, uni.BuiltinType) {
        return expr?.sym_name or str(getattr(expr, "value", ""));
    }
    if isinstance(expr, uni.AtomTrailer) {
        attrs = expr.as_attr_list;
        if attrs {
            last = attrs[-1];
            if isinstance(last, uni.Name) {
                return last.value;
            }
            if isinstance(last, uni.AstSymbolNode) {
                return last.sym_name;
            }
        }
    }
    return str(getattr(expr, "value", getattr(expr, "sym_name", "")));
}

"""Extract edge chains from an EdgeRefTrailer AST node."""
@classmethod
impl JacTTGGenerator._extract_chains_from_trailer(
    cls: type[JacTTGGenerator], scope: any, trailer: any
) -> list[tuple[str | None, str | None, int]] {
    import from typing { cast }
    edge_chain: list[tuple[str | None, str | None, int]] = [];
    chain_items = getattr(trailer, 'chain', []);
    for item in chain_items {
        step = cls._extract_edge_step(scope, item);
        if step[0] is not None or isinstance(item, uni.EdgeOpRef) {
            edge_chain.append(step);
        } elif step[1] is not None {
            if len(edge_chain) > 0 {
                prev: tuple[str | None, str | None, int] = edge_chain[-1];
                prev_dir: int = cast(int, prev[2]);
                edge_chain[-1] = (prev[0], step[1], prev_dir);
            }
        }
    }
    if len(edge_chain) == 0 {
        edge_refs = trailer.get_all_sub_nodes(uni.EdgeOpRef);
        for edge_ref in edge_refs {
            step = cls._extract_edge_step(scope, edge_ref);
            edge_chain.append(step);
        }
    }
    return edge_chain;
}

"""Extract all edge chains from any AST body (ability, method, etc).
Returns a list of edge chains — one per EdgeRefTrailer found."""
@classmethod
impl JacTTGGenerator._extract_refs_from_body(
    cls: type[JacTTGGenerator], body: any
) -> list[list[tuple[str | None, str | None, int]]] {
    result: list[list[tuple[str | None, str | None, int]]] = [];
    trailers = body.get_all_sub_nodes(uni.EdgeRefTrailer);
    for trailer in trailers {
        chain = cls._extract_chains_from_trailer(body, trailer);
        if len(chain) > 0 {
            result.append(chain);
        }
    }
    return result;
}

"""Resolve a function call's target symbol."""
@classmethod
impl JacTTGGenerator._call_target_symbol(
    cls: type[JacTTGGenerator], call: uni.FuncCall
) -> (uni.Symbol | None) {
    if isinstance(call.target, uni.Name) {
        sym = call.target.sym;
        if not sym and call.target.sym_tab {
            sym = call.target.sym_tab.lookup(call.target.sym_name, deep=True);
        }
        return sym;
    }
    if isinstance(call.target, uni.AtomTrailer) {
        attrs = call.target.as_attr_list;
        if attrs {
            last = attrs[-1];
            if isinstance(last, uni.AstSymbolNode) and last.sym {
                return last.sym;
            }
        }
    }
    return None;
}

"""Resolve a function call target to a Jac ability when possible."""
@classmethod
impl JacTTGGenerator._resolve_called_ability(
    cls: type[JacTTGGenerator], call: uni.FuncCall
) -> (uni.Ability | None) {
    sym = cls._call_target_symbol(call);
    if sym and sym.defn {
        defn_node = sym.defn[0];
        if isinstance(defn_node, uni.Ability) {
            return defn_node;
        }
        if defn_node.parent and isinstance(defn_node.parent, uni.Ability) {
            return defn_node.parent;
        }
    }

    # Fallback for older JIRs that do not preserve call-target symbols:
    # find a uniquely named archetype method in the enclosing module.
    method_name: (str | None) = None;
    target = call.target;
    if isinstance(target, uni.AtomTrailer) {
        names = target.get_all_sub_nodes(uni.Name);
        if len(names) > 0 {
            method_name = names[-1].value;
        }
    } elif isinstance(target, uni.NameAtom) {
        method_name = target.sym_name;
    }
    if method_name is None {
        return None;
    }
    module = call.find_parent_of_type(uni.Module);
    if module is None {
        return None;
    }
    for arch in module.get_all_sub_nodes(uni.Archetype) {
        for method in arch.get_all_sub_nodes(uni.Ability) {
            if method.py_resolve_name() == method_name {
                return method;
            }
        }
    }
    return None;
}

"""Infer the node type for a helper with one typed node parameter."""
@classmethod
impl JacTTGGenerator._single_param_node_type(
    cls: type[JacTTGGenerator], ability: uni.Ability
) -> (str | None) {
    if not isinstance(ability.signature, uni.FuncSignature) {
        return None;
    }
    params = ability.signature.get_parameters();
    if len(params) != 1 {
        return None;
    }
    tag = params[0].type_tag;
    if tag is None {
        return None;
    }
    type_name = cls._ast_type_name(tag.tag);
    if type_name is None {
        return None;
    }
    arch = cls._resolve_archetype(tag, type_name);
    if arch is None or arch.arch_type.name != Tok.KW_NODE {
        return None;
    }
    return arch.name.value;
}

"""Trace FuncCall nodes in an ability body, resolve to Jac callees,
and extract their refs expressions as VisitTypes."""
@classmethod
impl JacTTGGenerator._trace_method_calls(
    cls: type[JacTTGGenerator],
    ability: uni.Ability,
    current_node_type: (str | None) = None,
    seen: (set[int] | None) = None
) -> list[VisitType] {
    result: list[VisitType] = [];
    if seen is None {
        seen = set();
    }
    func_calls = cls._ability_sub_nodes(ability, uni.FuncCall);
    for call_any in func_calls {
        if not isinstance(call_any, uni.FuncCall) {
            continue;
        }
        call: uni.FuncCall = call_any;
        callee = cls._resolve_called_ability(call);
        if callee is None or id(callee) in seen {
            continue;
        }
        seen.add(id(callee));

        owner_type: (str | None) = None;
        if callee.method_owner and isinstance(callee.method_owner, uni.Archetype) {
            owner_type = callee.method_owner.name.value;
        }
        if owner_type is None {
            param_owner_type = cls._single_param_node_type(callee);
            if param_owner_type is not None {
                owner_type = param_owner_type;
            }
        }
        if owner_type is None and current_node_type is not None {
            owner_type = current_node_type;
        }

        trailers = cls._ability_sub_nodes(callee, uni.EdgeRefTrailer);
        for trailer in trailers {
            chain = cls._extract_chains_from_trailer(callee, trailer);
            if len(chain) > 0 {
                first_edge = chain[0][0] if len(chain) > 0 else None;
                result.append(
                    VisitType(
                        from_node_type=owner_type,
                        edge_type=first_edge,
                        edge_chain=chain if len(chain) > 0 else None,
                        is_visit=False
                    )
                );
            }
        }
        result.extend(cls._trace_method_calls(callee, owner_type, seen));
    }
    return result;
}

"""Extract visit types from a walker's AST at runtime.

Finds the walker's AST Archetype node, then for each ability with an
EventSignature:
  1. Extracts edge chains from VisitStmt nodes (explicit visit statements)
  2. Extracts edge chains from standalone refs expressions (EdgeRefTrailer
     outside of VisitStmt, e.g. `tweets = [self-->[?:Tweet]]`)
  3. Traces FuncCall nodes to resolve called methods on archetypes and
     extracts their refs expressions recursively

Results are returned as VisitType instances and cached on the walker class.
"""
@classmethod
impl JacTTGGenerator._extract_visits_from_ast(
    cls: type[JacTTGGenerator], warch: any
) -> list[VisitType] {
    warch_cls = `type(warch);
    # Check cache first.
    import from logging { getLogger as _cache_log }
    _cache_dbg = _cache_log(__name__);
    cached_raw = warch_cls?.__jac_ttg_visits__;
    if (isinstance(cached_raw, list) and len(cached_raw) > 0) {
        _cache_dbg.info(
            f"[TTG-EXTRACT] cache HIT for {warch_cls.__name__}, returning {len(
                cached_raw
            )} visits"
        );
        return cached_raw;
    }
    _cache_dbg.info(
        f"[TTG-EXTRACT] cache MISS for {warch_cls.__name__}, extracting from AST"
    );
    # Find the AST node for this walker.
    ast_node = cls._find_walker_ast_node(warch_cls);
    if ast_node is None {
        return [];
    }
    result: list[VisitType] = [];
    abilities = ast_node.get_all_sub_nodes(uni.Ability);
    for ability in abilities {
        event_sigs = ability.get_all_sub_nodes(uni.EventSignature);
        if len(event_sigs) == 0 {
            continue;
        }
        # Determine the from-node type from the event signature.
        node_type_name: (str | None) = None;
        node_type_names = event_sigs[0].get_all_sub_nodes(uni.Name);
        if len(node_type_names) > 0 {
            node_arch = cls._resolve_archetype(
                node_type_names[0], node_type_names[0].value
            );
            if node_arch is not None {
                node_type_name = node_arch.name.value;
            }
        }
        # 1. Extract from VisitStmt nodes (explicit visit statements).
        #    Descends into the ability's separately-defined `impl` body
        #    too, so `impl X.foo { visit [...] }` in another file lands
        #    here — see `_ability_sub_nodes` docstring.
        visit_stmts = cls._ability_sub_nodes(ability, uni.VisitStmt);
        for visit_stmt in visit_stmts {
            chains = cls._extract_refs_from_body(visit_stmt);
            for chain in chains {
                first_edge = chain[0][0] if len(chain) > 0 else None;
                result.append(
                    VisitType(
                        from_node_type=node_type_name,
                        edge_type=first_edge,
                        edge_chain=chain if len(chain) > 0 else None
                    )
                );
            }
        }
        # 2. Extract standalone refs expressions in the ability body
        #    (EdgeRefTrailer not inside a VisitStmt). These are data
        #    lookups (e.g. `mine = [root-->[?:Profile]]`), not walker
        #    visits — BFS prefetches their targets but does NOT expand
        #    further from them. Marked is_visit=False so the BFS treats
        #    the resolved targets as leaves.
        visit_trailer_ids: set[int] = set();
        for vs in visit_stmts {
            for t in vs.get_all_sub_nodes(uni.EdgeRefTrailer) {
                visit_trailer_ids.add(id(t));
            }
        }
        all_trailers = cls._ability_sub_nodes(ability, uni.EdgeRefTrailer);
        for trailer in all_trailers {
            if id(trailer) in visit_trailer_ids {
                continue;
            }
            chain = cls._extract_chains_from_trailer(ability, trailer);
            if len(chain) > 0 {
                first_edge = chain[0][0] if len(chain) > 0 else None;
                result.append(
                    VisitType(
                        from_node_type=node_type_name,
                        edge_type=first_edge,
                        edge_chain=chain if len(chain) > 0 else None,
                        is_visit=False
                    )
                );
            }
        }
        # 3. Trace into helper calls to extract data refs from called
        #    Jac functions/methods.
        method_visits = cls._trace_method_calls(ability, node_type_name);
        result.extend(method_visits);
    }
    # Cache on the class for subsequent calls.
    setattr(warch_cls, "__jac_ttg_visits__", result);
    return result;
}

"""Build a prefetch list by BFS over the topology index.

Single-pass BFS that resolves neighbors via resolve_chain() and collects
UUIDs for cache prefetching. Stops as soon as max_length nodes are found,
avoiding full graph traversal.

Supports multihop patterns: for visit [->:Follow:->->:Post:->], the full
chain is resolved in one call to resolve_chain(), directly reaching the
target nodes without intermediate BFS steps.
"""
@classmethod
impl JacTTGGenerator.get_ttg_prefetch_list(
    cls: type[JacTTGGenerator],
    warch: any,
    start_id: UUID,
    topology_index: TopologyIndex,
    mem: any = None,
    max_length: int = 200
) -> list[UUID] {
    import time as _time;
    _t0 = _time.perf_counter();
    visits = cls._extract_visits_from_ast(warch);
    _ast_ms = (_time.perf_counter() - _t0) * 1000;

    import from logging { getLogger as _dbg_log }
    _dbg = _dbg_log(__name__);
    _dbg.info(
        f"[TTG-DEBUG] extracted {len(visits)} visits: " + str(
            [
                (
                    f"from={cls._resolve_type_name(v.from_node_type)}",
                    f"edge={cls._resolve_type_name(v.edge_type)}",
                    f"chain={v.edge_chain}"
                ) for v in visits
            ]
        )
    );

    prefetch: list[UUID] = [start_id] if max_length > 0 else [];
    seen: set[UUID] = {start_id};
    import from collections { deque }
    import from collections { defaultdict }
    queue: deque[tuple[TopologyIndex, UUID]] = deque([(topology_index, start_id)]);
    prefetch_idx_by_id: dict[UUID, TopologyIndex] = {start_id: topology_index};
    _root_idx_cache: dict[UUID, TopologyIndex] = {};
    _support_root_ids: set[UUID] = set();
    _resolve_ms = 0.0;
    _resolve_calls = 0;
    _edge_count = 0;
    # Build adjacency index once: lid -> [(et, neighbor_lid)]
    # Avoids O(N²) full adj_list scan per node during BFS.
    _adj_index: dict = defaultdict(list);
    for (src_lid, _et, tgt_lid) in topology_index.adj_list {
        _adj_index[src_lid].append((_et, tgt_lid));
        _adj_index[tgt_lid].append((_et, src_lid));
    }
    while queue {
        if len(prefetch) >= max_length {
            break;
        }
        (cur_idx, cur) = queue.popleft();
        cur_lid = cur_idx.node_to_lid.get(cur);
        cur_type = cur_idx.type_table[cur_idx.node_table[cur_lid][1]]
            if cur_lid is not None
            else None;
        will_visit = False;
        for v in visits {
            from_type = cls._resolve_type_name(v.from_node_type)
                if isinstance(v, VisitType)
                else None;
            if from_type is not None and cur_type != from_type {
                continue;
            }
            will_visit = True;
            if isinstance(v, VisitType) and v.edge_chain is not None {
                chain = v.edge_chain;
            } elif isinstance(v, VisitType) {
                edge_name = cls._resolve_type_name(v.edge_type);
                chain = [(edge_name, None, 2)];
            } else {
                chain = [(None, None, 2)];
            }
            _rc_start = _time.perf_counter();
            if mem is not None {
                _results: set[UUID] = set();
                if not chain {
                    _results = {cur};
                } else {
                    _frontier: list[tuple[TopologyIndex, set[UUID]]] = [
                        (cur_idx, {cur})
                    ];
                    for (_hop_idx, _hop) in enumerate(chain) {
                        _is_last_hop = _hop_idx == len(chain) - 1;
                        _next_frontier: list[tuple[TopologyIndex, set[UUID]]] = [];
                        _hop_results_total: set[UUID] = set();
                        for (_idx, _ids) in _frontier {
                            _hop_result = _idx.resolve_chain(_ids, [_hop]) or set();
                            if not _hop_result {
                                continue;
                            }
                            if _is_last_hop {
                                _hop_results_total |= _hop_result;
                                continue;
                            }
                            _cross_root_map = _idx.get_cross_root_ids(_hop_result);
                            _foreign_ids: set[UUID] = set();
                            for _ids_for_root in _cross_root_map.values() {
                                _foreign_ids |= _ids_for_root;
                            }
                            _local_ids = _hop_result - _foreign_ids;
                            if _local_ids {
                                _next_frontier.append((_idx, _local_ids));
                            }
                            for (_foreign_root_id, _foreign_node_ids) in _cross_root_map.items() {
                                _cached_idx = _root_idx_cache.get(_foreign_root_id);
                                if _cached_idx is None {
                                    if _foreign_root_id not in seen {
                                        if len(prefetch) >= max_length {
                                            continue;
                                        }
                                        seen.add(_foreign_root_id);
                                        prefetch.append(_foreign_root_id);
                                        prefetch_idx_by_id[_foreign_root_id] = _idx;
                                        _support_root_ids.add(_foreign_root_id);
                                        try {
                                            mem.prefetch([_foreign_root_id]);
                                        } except Exception {
                                            ;
                                        }
                                    }
                                    try {
                                        _root_anchor = cls._get_support_root_anchor(
                                            mem, _foreign_root_id
                                        );
                                        if isinstance(_root_anchor, NodeAnchor) {
                                            _maybe_idx = _root_anchor.get_topology_index();
                                            if isinstance(_maybe_idx, TopologyIndex)
                                            and len(_maybe_idx) > 0 {
                                                _cached_idx = _maybe_idx;
                                                _root_idx_cache[_foreign_root_id] = _maybe_idx;
                                            }
                                        }
                                    } except Exception {
                                        ;
                                    }
                                }
                                if _cached_idx is not None and len(_cached_idx) > 0 {
                                    _next_frontier.append(
                                        (_cached_idx, _foreign_node_ids)
                                    );
                                }
                            }
                        }
                        if _is_last_hop {
                            _results = _hop_results_total;
                            break;
                        }
                        _frontier = _next_frontier;
                        if not _frontier {
                            _results = set();
                            break;
                        }
                    }
                }
            } else {
                _results = cur_idx.resolve_chain({cur}, chain) or set();
            }
            _resolve_ms += (_time.perf_counter() - _rc_start) * 1000;
            _resolve_calls += 1;
            # Walker-visit chains propagate the BFS frontier; data-lookup
            # chains (inline edge-refs, traced method bodies) produce
            # leaves that get prefetched but never re-expanded. Without
            # this distinction the BFS over-expands an order of magnitude
            # past what the walker will actually read.
            _is_visit_chain = (not isinstance(v, VisitType)) or v.is_visit;
            _added = 0;
            _enqueued = 0;
            for tgt in _results {
                if tgt not in seen {
                    if len(prefetch) >= max_length {
                        break;
                    }
                    seen.add(tgt);
                    prefetch.append(tgt);
                    _target_idx = cur_idx;
                    _can_enqueue_target = _is_visit_chain;
                    if mem is not None and _is_visit_chain {
                        try {
                            _cross_root_map = cur_idx.get_cross_root_ids({tgt});
                            for (_foreign_root_id, _foreign_node_ids) in _cross_root_map.items() {
                                if tgt in _foreign_node_ids {
                                    _cached_idx = _root_idx_cache.get(_foreign_root_id);
                                    if _cached_idx is None {
                                        if _foreign_root_id not in seen {
                                            if len(prefetch) < max_length {
                                                seen.add(_foreign_root_id);
                                                prefetch.append(_foreign_root_id);
                                                prefetch_idx_by_id[_foreign_root_id] = cur_idx;
                                                _support_root_ids.add(_foreign_root_id);
                                                try {
                                                    mem.prefetch([_foreign_root_id]);
                                                } except Exception {
                                                    ;
                                                }
                                            } else {
                                                _can_enqueue_target = False;
                                            }
                                        }
                                        if _can_enqueue_target {
                                            _root_anchor = cls._get_support_root_anchor(
                                                mem, _foreign_root_id
                                            );
                                            if isinstance(_root_anchor, NodeAnchor) {
                                                _maybe_idx = _root_anchor.get_topology_index();
                                                if isinstance(_maybe_idx, TopologyIndex)
                                                and len(_maybe_idx) > 0 {
                                                    _cached_idx = _maybe_idx;
                                                    _root_idx_cache[_foreign_root_id] = _maybe_idx;
                                                }
                                            }
                                        }
                                    }
                                    if _cached_idx is not None
                                    and len(_cached_idx) > 0 {
                                        _target_idx = _cached_idx;
                                    } else {
                                        _can_enqueue_target = False;
                                    }
                                    break;
                                }
                            }
                        } except Exception {
                            ;
                        }
                    }
                    prefetch_idx_by_id[tgt] = _target_idx;
                    _added += 1;
                    if _can_enqueue_target {
                        queue.append((_target_idx, tgt));
                        _enqueued += 1;
                    }
                    if len(prefetch) >= max_length {
                        break;
                    }
                }
            }
            if _added > 0 {
                _vis_flag = "n/a";
                if isinstance(v, VisitType) {
                    _vis_flag = str(v.is_visit);
                }
                _dbg.info(
                    f"[TTG-BFS] cur_type={cur_type} "
                    f"from={cls._resolve_type_name(v.from_node_type)} "
                    f"is_visit={_vis_flag} "
                    f"chain_results={len(_results)} "
                    f"added={_added} enqueued={_enqueued}"
                );
            }
            if len(prefetch) >= max_length {
                break;
            }
        }
        # Edge prefetch skipped: the topology index resolves traversal
        # paths directly to target node IDs without materializing edges.
        # Walkers with edge-triggered abilities would need this restored.
    }
    import from logging { getLogger as _getLogger }
    _avg_resolve = _resolve_ms / _resolve_calls if _resolve_calls > 0 else 0.0;
    # Count prefetched nodes by type
    _type_counts: dict[str, int] = {};
    for _pid in prefetch {
        if _pid in _support_root_ids {
            _ptype = "Root";
        } else {
            _pidx = prefetch_idx_by_id.get(_pid) or topology_index;
            _plid = _pidx.node_to_lid.get(_pid);
            if _plid is not None {
                _ptype = str(_pidx.type_table[_pidx.node_table[_plid][1]]);
            } else {
                _ptype = "unknown";
            }
        }
        _type_counts[_ptype] = _type_counts.get(_ptype, 0) + 1;
    }
    # Count total nodes in index by type
    _idx_type_counts: dict[str, int] = {};
    for (_nid, _tid, _owner) in topology_index.node_table {
        _tname = topology_index.type_table[_tid];
        _idx_type_counts[_tname] = _idx_type_counts.get(_tname, 0) + 1;
    }
    _getLogger(__name__).info(
        f"[TTG] ast_ms={_ast_ms:.3f}  resolve_chain_total_ms={_resolve_ms:.3f}"
        f"  resolve_calls={_resolve_calls}  avg_per_call_ms={_avg_resolve:.4f}"
        f"  nodes_in_adj={len(topology_index.adj_list)}"
        f"  prefetched={len(prefetch)}  nodes={len(prefetch) - _edge_count}  edges={_edge_count}"
    );
    _getLogger(__name__).info(
        f"[TTG-COVERAGE] prefetched_by_type={_type_counts}  "
        f"index_by_type={_idx_type_counts}  max_length={max_length}"
    );
    # DEBUG: confirm is_visit flag is being seen
    _is_visit_dbg: list = [];
    for v in visits {
        if isinstance(v, VisitType) {
            _is_visit_dbg.append(
                (cls._resolve_type_name(v.from_node_type), v.is_visit)
            );
        }
    }
    _getLogger(__name__).info(f"[TTG-IS-VISIT-DBG] {_is_visit_dbg}");
    # Optional dump of the prefetch list to disk for offline inspection.
    # Triggered by `JAC_PREFETCH_DUMP=<path>`. Writes one CSV row per id
    # with type ("unknown" when not in the local topology_index) and the
    # owning Root when known. Appends, so successive walker spawns in a
    # long-lived server accumulate.
    import os as _os;
    _dump_path = _os.environ.get("JAC_PREFETCH_DUMP");
    if _dump_path {
        try {
            import pathlib as _pathlib;
            _p = _pathlib.Path(_dump_path);
            _p.parent.mkdir(parents=True, exist_ok=True);
            _new_file = not _p.exists();
            with _p.open("a") as _fh {
                if _new_file {
                    _fh.write("id,type,owner\n");
                }
                for _pid in prefetch {
                    if _pid in _support_root_ids {
                        _fh.write(f"{_pid},Root,\n");
                    } else {
                        _pidx = prefetch_idx_by_id.get(_pid) or topology_index;
                        _plid = _pidx.node_to_lid.get(_pid);
                        if _plid is not None {
                            (_nid, _tid, _owner) = _pidx.node_table[_plid];
                            _ptype = _pidx.type_table[_tid];
                            _fh.write(f"{_pid},{_ptype},{_owner}\n");
                        } else {
                            _fh.write(f"{_pid},unknown,\n");
                        }
                    }
                }
            }
        } except Exception as _e {
            _getLogger(__name__).debug(f"[PREFETCH-DUMP] write failed: {_e}");
        }
    }
    setattr(cls, "_last_resolve_ms", _resolve_ms);
    return prefetch;
}
