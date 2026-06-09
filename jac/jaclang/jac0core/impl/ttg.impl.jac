"""Implementation for TTG Generator constructs."""

import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.archetype { VisitType }
import from jaclang.jac0core.constant { Tokens as Tok }

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
    cls: type[JacTTGGenerator], scope_src: uni.UniNode, name: str
) -> (uni.Archetype | None) {
    scope = scope_src.find_parent_of_type(uni.UniScopeNode);
    if scope is None {
        return None;
    }
    result = scope.lookup(name);
    if result is None {
        return None;
    }
    return result.decl.find_parent_of_type(uni.Archetype);
}

"""Extract edge type and optional node filter from an EdgeOpRef or FilterCompr."""
@classmethod
impl JacTTGGenerator._extract_edge_step(
    cls: type[JacTTGGenerator], scope: uni.UniNode, item: uni.UniNode
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

"""Extract edge chains from an EdgeRefTrailer AST node."""
@classmethod
impl JacTTGGenerator._extract_chains_from_trailer(
    cls: type[JacTTGGenerator], scope: uni.UniNode, trailer: uni.EdgeRefTrailer
) -> list[tuple[str | None, str | None, int]] {
    edge_chain: list[tuple[str | None, str | None, int]] = [];
    chain_items = getattr(trailer, 'chain', []);
    for item in chain_items {
        step = cls._extract_edge_step(scope, item);
        if step[0] is not None or isinstance(item, uni.EdgeOpRef) {
            edge_chain.append(step);
        } elif step[1] is not None {
            if len(edge_chain) > 0 {
                prev = edge_chain[-1];
                edge_chain[-1] = (prev[0], step[1], prev[2]);
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
    cls: type[JacTTGGenerator], body: uni.UniNode
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

"""Trace FuncCall nodes in an ability body, resolve to archetype methods,
and extract their refs expressions as VisitTypes."""
@classmethod
impl JacTTGGenerator._trace_method_calls(
    cls: type[JacTTGGenerator], ability: uni.Ability
) -> list[VisitType] {
    result: list[VisitType] = [];
    seen_methods: set[str] = set();
    func_calls = ability.get_all_sub_nodes(uni.FuncCall);
    for call in func_calls {
        # Resolve the function name. For attr access (e.g. here.to_profile_view()),
        # we need the method name. For simple calls, use the target name directly.
        method_name: (str | None) = None;
        if isinstance(call.target, uni.AtomTrailer) {
            # e.g. here.to_profile_view() — get the last Name in the chain
            names = call.target.get_all_sub_nodes(uni.Name);
            if len(names) > 0 {
                method_name = names[-1].value;
            }
        } elif isinstance(call.target, uni.NameAtom) {
            method_name = call.target.value;
        }
        if method_name is None or method_name in seen_methods {
            continue;
        }
        seen_methods.add(method_name);
        # Try to resolve via symbol table
        resolved_arch = cls._resolve_archetype(call, method_name);
        if resolved_arch is not None {
            # Found the archetype — look for the method within it
            for method in resolved_arch.get_all_sub_nodes(uni.Ability) {
                if method.name_ref is not None
                and method.name_ref.value == method_name {
                    # Extract refs from this method body
                    chains = cls._extract_refs_from_body(method);
                    owner_type = resolved_arch.name.value;
                    for chain in chains {
                        first_edge = chain[0][0] if len(chain) > 0 else None;
                        result.append(
                            VisitType(
                                from_node_type=owner_type,
                                edge_type=first_edge,
                                edge_chain=chain if len(chain) > 0 else None
                            )
                        );
                    }
                    break;
                }
            }
            continue;
        }
        # Fallback: try to find the method on any archetype in the module
        # by searching all archetypes for a matching ability name.
        module = ability.find_parent_of_type(uni.Module);
        if module is None {
            continue;
        }
        for arch in module.get_all_sub_nodes(uni.Archetype) {
            for method in arch.get_all_sub_nodes(uni.Ability) {
                if method.name_ref is not None
                and method.name_ref.value == method_name {
                    chains = cls._extract_refs_from_body(method);
                    owner_type = arch.name.value;
                    for chain in chains {
                        first_edge = chain[0][0] if len(chain) > 0 else None;
                        result.append(
                            VisitType(
                                from_node_type=owner_type,
                                edge_type=first_edge,
                                edge_chain=chain if len(chain) > 0 else None
                            )
                        );
                    }
                    break;
                }
            }
        }
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
    cls: type[JacTTGGenerator], warch: Any
) -> list[VisitType] {
    warch_cls = `type(warch);
    # Check cache first.
    import from logging { getLogger as _cache_log }
    _cache_dbg = _cache_log(__name__);
    cached = warch_cls?.__jac_ttg_visits__;
    if (cached is not None and len(cached) > 0) {
        _cache_dbg.info(
            f"[TTG-EXTRACT] cache HIT for {warch_cls.__name__}, returning {len(
                cached
            )} visits"
        );
        return cached;
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
        visit_stmts = ability.get_all_sub_nodes(uni.VisitStmt);
        import from logging { getLogger as _ext_log }
        _ext_dbg = _ext_log(__name__);
        for visit_stmt in visit_stmts {
            chains = cls._extract_refs_from_body(visit_stmt);
            # Check if the visit target starts from a local variable
            # (e.g. `visit [me-->...]`). If so, we don't know the type
            # of the starting node, so use None (wildcard).
            visit_from = node_type_name;
            chain_items = getattr(visit_stmt.target, 'chain', []);
            if chain_items and isinstance(chain_items[0], uni.Name) {
                root_name = chain_items[0].value;
                if root_name not in ('self', 'here') {
                    visit_from = None;
                }
            }
            for chain in chains {
                first_edge = chain[0][0] if len(chain) > 0 else None;
                result.append(
                    VisitType(
                        from_node_type=visit_from,
                        edge_type=first_edge,
                        edge_chain=chain if len(chain) > 0 else None
                    )
                );
            }
        }
        # 2. Extract standalone refs expressions in the ability body
        #    (EdgeRefTrailer not inside a VisitStmt).
        visit_trailer_ids: set[int] = set();
        for vs in visit_stmts {
            for t in vs.get_all_sub_nodes(uni.EdgeRefTrailer) {
                visit_trailer_ids.add(id(t));
            }
        }
        all_trailers = ability.get_all_sub_nodes(uni.EdgeRefTrailer);
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
                        edge_chain=chain if len(chain) > 0 else None
                    )
                );
            }
        }
        # 3. Trace into method calls to extract refs from called methods.
        method_visits = cls._trace_method_calls(ability);
        result.extend(method_visits);
    }
    # Cache on the class for subsequent calls.
    warch_cls.__jac_ttg_visits__ = result;
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
    warch: Any,
    start_id: UUID,
    topology_index: Any,
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

    prefetch: list[UUID] = [start_id];
    seen: set[UUID] = {start_id};
    import from collections { deque }
    import from collections { defaultdict }
    queue: deque = deque([start_id]);
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
        cur = queue.popleft();
        cur_lid = topology_index.node_to_lid.get(cur);
        cur_type = topology_index.type_table[topology_index.node_table[cur_lid][1]]
            if cur_lid is not None
            else None;
        _dbg.info(
            f"[TTG-DEBUG] BFS node: cur_lid={cur_lid}, cur_type={cur_type}, cur={cur}"
        );
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
            _dbg.info(f"[TTG-DEBUG]   match: from_type={from_type}, chain={chain}");
            _rc_start = _time.perf_counter();
            _results = topology_index.resolve_chain({cur}, chain);
            _resolve_ms += (_time.perf_counter() - _rc_start) * 1000;
            _dbg.info(f"[TTG-DEBUG]   resolve_chain returned {len(_results)} results");
            _resolve_calls += 1;
            for tgt in _results {
                if tgt not in seen {
                    seen.add(tgt);
                    prefetch.append(tgt);
                    queue.append(tgt);
                    if len(prefetch) >= max_length {
                        break;
                    }
                }
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
    _getLogger(__name__).info(
        f"[TTG] ast_ms={_ast_ms:.3f}  resolve_chain_total_ms={_resolve_ms:.3f}"
        f"  resolve_calls={_resolve_calls}  avg_per_call_ms={_avg_resolve:.4f}"
        f"  nodes_in_adj={len(topology_index.adj_list)}"
        f"  prefetched={len(prefetch)}  nodes={len(prefetch) - _edge_count}  edges={_edge_count}"
    );
    cls._last_resolve_ms = _resolve_ms;
    return prefetch;
}
