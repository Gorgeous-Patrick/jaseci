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

"""Find the AST Archetype node for a walker class via JacProgram.mod.hub.

Uses the class's __module__ to locate the Python module, then its __file__
to look up the AST Module in the program hub. Searches for an Archetype
node whose name matches the class name and whose arch_type is KW_WALKER.
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
    file_path = getattr(py_module, '__file__', None);
    if file_path is None {
        return None;
    }
    # Look up the AST Module from the program hub.
    ast_module = program.mod.hub.get(file_path);
    if ast_module is None {
        # Try all hub modules as fallback (file paths may differ).
        for mod in program.mod.hub.values() {
            for arch in mod.get_all_sub_nodes(uni.Archetype) {
                if (
                    arch.arch_type.name == Tok.KW_WALKER
                    and arch.name.value == class_name
                ) {
                    return arch;
                }
            }
        }
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

"""Extract visit types from a walker's AST at runtime.

Finds the walker's AST Archetype node, then for each ability with an
EventSignature extracts the from-node type, and for each VisitStmt
extracts the edge type from EdgeOpRef filter conditions. Results are
returned as VisitType instances and cached on the walker class.
"""
@classmethod
impl JacTTGGenerator._extract_visits_from_ast(
    cls: type[JacTTGGenerator], warch: Any
) -> list[VisitType] {
    warch_cls = `type(warch);
    # Check cache first.
    cached = getattr(warch_cls, '__jac_ttg_visits__', None);
    if (cached is not None and len(cached) > 0) {
        return cached;
    }
    # Find the AST node for this walker.
    ast_node = cls._find_walker_ast_node(warch_cls);
    if ast_node is None {
        return [];
    }
    # Extract visits using the same logic as the old JacTTGPass.
    result: list[VisitType] = [];
    abilities = ast_node.get_all_sub_nodes(uni.Ability);
    for ability in abilities {
        event_sigs = ability.get_all_sub_nodes(uni.EventSignature);
        if (len(event_sigs) == 0) {
            continue;
        }
        # Determine the from-node type from the event signature.
        node_type_name: (str | None) = None;
        node_type_names = event_sigs[0].get_all_sub_nodes(uni.Name);
        if (len(node_type_names) > 0) {
            node_arch = cls._resolve_archetype(
                node_type_names[0], node_type_names[0].value
            );
            if node_arch is not None {
                node_type_name = node_arch.name.value;
            }
        }
        # Collect visit statements within this ability.
        visit_stmts = ability.get_all_sub_nodes(uni.VisitStmt);
        for visit_stmt in visit_stmts {
            # Extract edge type from the visit statement.
            edge_type_name: (str | None) = None;
            edge_refs = visit_stmt.get_all_sub_nodes(uni.EdgeOpRef);
            if (len(edge_refs) > 0) {
                edge_ref = edge_refs[0];
                fc = getattr(edge_ref, 'filter_cond', None);
                if fc is not None {
                    ft = getattr(fc, 'f_type', None);
                    if ft is not None {
                        names = fc.get_all_sub_nodes(uni.Name);
                        if (len(names) > 0) {
                            edge_arch = cls._resolve_archetype(
                                visit_stmt, names[0].value
                            );
                            if edge_arch is not None {
                                edge_type_name = edge_arch.name.value;
                            }
                        }
                    }
                }
            }
            result.append(
                VisitType(from_node_type=node_type_name, edge_type=edge_type_name)
            );
        }
    }
    # Cache on the class for subsequent calls.
    warch_cls.__jac_ttg_visits__ = result;
    return result;
}

"""Build a temporal trace graph using TopologyIndex.

Uses the TopologyIndex's resolve_chain() to walk the adjacency list
with type-only filters for each visit type. BFS expansion from start_id.
Visit types are extracted lazily from the AST on first call.
"""
@classmethod
impl JacTTGGenerator.get_ttg(
    cls: type[JacTTGGenerator], warch: Any, start_id: UUID, topology_index: Any
) -> tuple {
    wtype_name = `type(warch).__name__;
    visits = cls._extract_visits_from_ast(warch);
    ttg_root = TypedWalkerState(
        walker_type=wtype_name, depth=0, nd=start_id, incoming_edge=None, children=[]
    );
    visited_ids: set[UUID] = `set();
    child_map: dict = {};
    queue: list[TypedWalkerState] = [ttg_root];
    while queue {
        state = queue.pop(0);
        cur = state.nd;
        for v in visits {
            if isinstance(v, VisitType) {
                edge_name = cls._resolve_type_name(v.edge_type);
                chain = [(edge_name, None, 2)];
                neighbors = topology_index.resolve_chain({cur}, chain);
            } else {
                chain = [(None, None, 2)];
                neighbors = topology_index.resolve_chain({cur}, chain);
            }
            for tgt in neighbors {
                if (tgt in visited_ids) {
                    continue;
                }
                visited_ids.add(tgt);
                child_map.setdefault(cur, []).append(tgt);
                child_state = TypedWalkerState(
                    walker_type=wtype_name,
                    nd=tgt,
                    depth=state.depth + 1,
                    incoming_edge=None,
                    children=[]
                );
                state.children.append(child_state);
                queue.append(child_state);
            }
        }
    }
    return (ttg_root, visited_ids, child_map);
}

"""Build a prefetch list from TTG child_map.

BFS traversal of the child_map to produce an ordered list of UUIDs
for cache prefetching.
"""
@classmethod
impl JacTTGGenerator.get_prefetch_list(
    cls: type[JacTTGGenerator], start: UUID, ttg_children: dict, max_length: int = 200
) -> list[UUID] {
    prefetch: list[UUID] = [];
    seen: set[UUID] = `set();
    def _add(uid: UUID) -> None {
        if (uid not in seen) {
            seen.add(uid);
            prefetch.append(uid);
        }
    }
    queue: list[UUID] = [start];
    while queue {
        nid = queue.pop(0);
        _add(nid);
        children = ttg_children.get(nid, []);
        for child_nid in children {
            if (child_nid not in seen) {
                queue.append(child_nid);
            }
        }
        if (len(prefetch) >= max_length) {
            break;
        }
    }
    return prefetch[:max_length];
}
