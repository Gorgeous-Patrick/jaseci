"""Implementation for TTG prefetch planning."""

import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.archetype { VisitType }
import from jaclang.jac0core.constant { Tokens as Tok }
import from typing { cast }

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

@classmethod
impl JacTTGGenerator._find_walker_ast_node(
    cls: type[JacTTGGenerator], warch_cls: type
) -> (uni.Archetype | None) {
    import sys;
    import from jaclang.jac0core.runtime { JacRuntime }

    program = JacRuntime.get_program();
    module_name = warch_cls.__module__;
    class_name = warch_cls.__name__;
    py_module: any = None;
    sys_module: any = sys.modules.get(module_name);
    loaded_module: any = JacRuntime.loaded_modules.get(module_name);
    for candidate in [sys_module, loaded_module] {
        if candidate is None {
            continue;
        }
        if getattr(candidate, class_name, None) is warch_cls {
            py_module = candidate;
            break;
        }
    }
    if py_module is None {
        py_module = sys_module if sys_module is not None else loaded_module;
    }
    if py_module is None {
        return None;
    }
    raw_file_path = py_module?.__file__;
    if raw_file_path is None {
        return None;
    }
    file_path: str = str(raw_file_path);

    hub: any = program.mod.hub;
    ast_module: (uni.Module | None) = cast(uni.Module | None, hub.get(file_path));
    if ast_module is None {
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
                    hub[file_path] = ast_module;
                }
            }
        } except Exception {
            ;
        }
    }
    if ast_module is None {
        return None;
    }
    for raw_arch in ast_module.get_all_sub_nodes(uni.Archetype) {
        arch = cast(uni.Archetype, raw_arch);
        if arch.arch_type.name == Tok.KW_WALKER and arch.name.value == class_name {
            return arch;
        }
    }
    return None;
}

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

@classmethod
impl JacTTGGenerator._extract_edge_step(
    cls: type[JacTTGGenerator], scope: uni.UniNode, item: uni.UniNode
) -> tuple[str | None, str | None, int] {
    edge_type_name: (str | None) = None;
    node_filter_name: (str | None) = None;
    direction = 2;
    if isinstance(item, uni.EdgeOpRef) {
        fc = item?.filter_cond;
        if fc is not None {
            ft = fc?.f_type;
            if ft is not None {
                type_name: (str | None) = None;
                if isinstance(ft, uni.Name) {
                    type_name = ft.value;
                } else {
                    names = ft.get_all_sub_nodes(uni.Name);
                    if len(names) > 0 {
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
        edge_dir = item?.edge_dir;
        if edge_dir is not None {
            dir_name = getattr(edge_dir, 'name', '');
            if 'IN' in str(dir_name) {
                direction = 1;
            } elif 'OUT' in str(dir_name) {
                direction = 2;
            } else {
                direction = 3;
            }
        }
    } elif isinstance(item, uni.FilterCompr) {
        ft = item?.f_type;
        if ft is not None {
            type_name: (str | None) = None;
            if isinstance(ft, uni.Name) {
                type_name = ft.value;
            } else {
                names = ft.get_all_sub_nodes(uni.Name);
                if len(names) > 0 {
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

@classmethod
impl JacTTGGenerator._ability_sub_nodes(
    cls: type[JacTTGGenerator], ability: uni.Ability, node_type: type
) -> list[uni.UniNode] {
    result: list[uni.UniNode] = cast(
        list[uni.UniNode], ability.get_all_sub_nodes(node_type)
    );
    body = ability?.body;
    if isinstance(body, uni.ImplDef) {
        result.extend(cast(list[uni.UniNode], body.get_all_sub_nodes(node_type)));
    }
    return result;
}

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
        } elif step[1] is not None and len(edge_chain) > 0 {
            prev = edge_chain[-1];
            edge_chain[-1] = (prev[0], step[1], prev[2]);
        }
    }
    if len(edge_chain) == 0 {
        edge_refs = trailer.get_all_sub_nodes(uni.EdgeOpRef);
        for edge_ref in edge_refs {
            edge_chain.append(cls._extract_edge_step(scope, edge_ref));
        }
    }
    return edge_chain;
}

@classmethod
impl JacTTGGenerator._extract_refs_from_body(
    cls: type[JacTTGGenerator], body: uni.UniNode
) -> list[list[tuple[str | None, str | None, int]]] {
    result: list[list[tuple[str | None, str | None, int]]] = [];
    for trailer in body.get_all_sub_nodes(uni.EdgeRefTrailer) {
        chain = cls._extract_chains_from_trailer(body, trailer);
        if len(chain) > 0 {
            result.append(chain);
        }
    }
    return result;
}

@classmethod
impl JacTTGGenerator._trace_method_calls(
    cls: type[JacTTGGenerator], ability: uni.Ability
) -> list[VisitType] {
    result: list[VisitType] = [];
    seen_methods: set[str] = set();
    for raw_call in cls._ability_sub_nodes(ability, uni.FuncCall) {
        if not isinstance(raw_call, uni.FuncCall) {
            continue;
        }
        call = cast(uni.FuncCall, raw_call);
        method_name: (str | None) = None;
        if isinstance(call.target, uni.AtomTrailer) {
            names: list[uni.Name] = cast(
                list[uni.Name], call.target.get_all_sub_nodes(uni.Name)
            );
            if len(names) > 0 {
                method_name = names[-1].value;
            }
        } elif isinstance(call.target, uni.Name) {
            method_name = call.target.value;
        } elif isinstance(call.target, uni.NameAtom) {
            method_name = call.target.sym_name;
        }
        if method_name is None or method_name in seen_methods {
            continue;
        }
        seen_methods.add(method_name);

        resolved_arch = cls._resolve_archetype(call, method_name);
        archetypes: list[uni.Archetype] = [];
        if resolved_arch is not None {
            archetypes.append(resolved_arch);
        } else {
            module = ability.find_parent_of_type(uni.Module);
            if module is not None {
                archetypes = cast(
                    list[uni.Archetype],
                    module.get_all_sub_nodes(uni.Archetype)
                );
            }
        }
        for arch in archetypes {
            matched = False;
            for raw_method in arch.get_all_sub_nodes(uni.Ability) {
                method = cast(uni.Ability, raw_method);
                if method.name_ref is None {
                    continue;
                }
                method_ref_name = (
                    method.name_ref.value
                    if isinstance(method.name_ref, uni.Name)
                    else method.name_ref.sym_name
                );
                if method_ref_name == method_name {
                    owner_type = arch.name.value;
                    for chain in cls._extract_refs_from_body(method) {
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
                    matched = True;
                    break;
                }
            }
            if matched {
                break;
            }
        }
    }
    return result;
}

@classmethod
impl JacTTGGenerator._extract_visits_from_ast(
    cls: type[JacTTGGenerator], warch: any
) -> list[VisitType] {
    warch_cls = `type(warch);
    cached_any: any = getattr(warch_cls, '__jac_ttg_visits__', None);
    cached: list[VisitType] = (
        cast(list[VisitType], cached_any) if isinstance(cached_any, list) else []
    );
    if len(cached) > 0 {
        return cached;
    }
    ast_node = cls._find_walker_ast_node(warch_cls);
    if ast_node is None {
        return [];
    }
    result: list[VisitType] = [];
    for raw_ability in ast_node.get_all_sub_nodes(uni.Ability) {
        ability = cast(uni.Ability, raw_ability);
        event_sigs: list[uni.EventSignature] = cast(
            list[uni.EventSignature],
            ability.get_all_sub_nodes(uni.EventSignature)
        );
        if len(event_sigs) == 0 {
            continue;
        }
        node_type_name: (str | None) = None;
        node_type_names: list[uni.Name] = cast(
            list[uni.Name], event_sigs[0].get_all_sub_nodes(uni.Name)
        );
        if len(node_type_names) > 0 {
            node_arch = cls._resolve_archetype(
                node_type_names[0], node_type_names[0].value
            );
            if node_arch is not None {
                node_type_name = node_arch.name.value;
            }
        }

        visit_stmts: list[uni.VisitStmt] = [];
        for raw_visit_stmt in cls._ability_sub_nodes(ability, uni.VisitStmt) {
            if isinstance(raw_visit_stmt, uni.VisitStmt) {
                visit_stmts.append(cast(uni.VisitStmt, raw_visit_stmt));
            }
        }
        for visit_stmt in visit_stmts {
            for chain in cls._extract_refs_from_body(visit_stmt) {
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

        visit_trailer_ids: set[int] = set();
        for vs in visit_stmts {
            for raw_trailer in vs.get_all_sub_nodes(uni.EdgeRefTrailer) {
                trailer = cast(uni.EdgeRefTrailer, raw_trailer);
                visit_trailer_ids.add(id(trailer));
            }
        }
        for raw_trailer in cls._ability_sub_nodes(ability, uni.EdgeRefTrailer) {
            if not isinstance(raw_trailer, uni.EdgeRefTrailer) {
                continue;
            }
            trailer = cast(uni.EdgeRefTrailer, raw_trailer);
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
        result.extend(cls._trace_method_calls(ability));
    }
    setattr(warch_cls, '__jac_ttg_visits__', result);
    return result;
}

@classmethod
impl JacTTGGenerator.get_ttg_prefetch_list(
    cls: type[JacTTGGenerator],
    warch: any,
    start_id: UUID,
    topology_index: any,
    mem: any = None,
    max_length: int = 200
) -> list[UUID] {
    import time as _time;
    import from collections { deque }
    import from logging { getLogger as _get_logger }

    visits = cls._extract_visits_from_ast(warch);
    logger = _get_logger(__name__);
    if not visits {
        return [start_id];
    }

    prefetch: list[UUID] = [start_id];
    seen: set[UUID] = {start_id};
    queue: deque = deque([start_id]);
    resolve_ms = 0.0;
    resolve_calls = 0;

    while queue and len(prefetch) < max_length {
        cur = queue.popleft();
        cur_lid = topology_index.node_to_lid.get(cur);
        cur_type = (
            topology_index.type_table[topology_index.node_table[cur_lid][1]]
            if cur_lid is not None
            else None
        );
        for visit in visits {
            from_type = cls._resolve_type_name(visit.from_node_type);
            if from_type is not None and cur_type != from_type {
                continue;
            }
            if visit.edge_chain is not None {
                chain = visit.edge_chain;
            } else {
                chain = [(cls._resolve_type_name(visit.edge_type), None, 2)];
            }
            start = _time.perf_counter();
            resolved = topology_index.resolve_chain({cur}, chain) or set();
            resolve_ms += (_time.perf_counter() - start) * 1000;
            resolve_calls += 1;
            for target_id in resolved {
                if target_id in seen {
                    continue;
                }
                seen.add(target_id);
                prefetch.append(target_id);
                if visit.is_visit {
                    queue.append(target_id);
                }
                if len(prefetch) >= max_length {
                    break;
                }
            }
            if len(prefetch) >= max_length {
                break;
            }
        }
    }

    avg_ms = resolve_ms / resolve_calls if resolve_calls > 0 else 0.0;
    logger.debug(
        f"[TTG] visits={len(visits)} resolve_calls={resolve_calls} "
        f"resolve_ms={resolve_ms:.3f} avg_ms={avg_ms:.4f} "
        f"prefetched={len(prefetch)} max_length={max_length}"
    );
    setattr(cls, '_last_resolve_ms', resolve_ms);
    return prefetch;
}
