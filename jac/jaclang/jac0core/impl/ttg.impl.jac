"""Implementation for TTG Generator constructs.

Optimized version: pre-built adjacency map for O(1) neighbor lookup,
deque-based BFS, cached reverse type map, and pre-resolved visit types.
"""
import from jaclang.jac0core.archetype { VisitType }

"""Resolve a VisitType field (type or string name) to a concrete type.

Looks up string names in the reverse_type_map (name -> type) built from
type_map values. Returns None if unresolved.
"""
@ classmethod
impl JacTTGGenerator._resolve_type(
    cls: type[JacTTGGenerator],
    ref: (type | str | None),
    reverse_type_map: dict[(str, type)]
) -> (type | None) {
    if ref is None {
        return None;
    }
    if isinstance(ref, str) {
        return reverse_type_map.get(ref);
    }
    return ref;
}

"""Pre-filter walker visits applicable to a given node type.

Separates visit type checking from edge matching so the node-type
filter runs once per BFS node rather than once per edge.
"""
@ classmethod
impl JacTTGGenerator._applicable_visits(
    cls: type[JacTTGGenerator],
    nd_type: (type | None),
    visits: list,
    reverse_type_map: dict[(str, type)]
) -> list {
    result: list = [];
    for v in visits {
        if not isinstance(v, VisitType) {
            result.append(v);
            continue;
        }
        resolved_from = cls._resolve_type(v.from_node_type, reverse_type_map);
        if (
            v.from_node_type is None
            or resolved_from is None
            or (nd_type is not None and issubclass(nd_type, resolved_from))
        ) {
            result.append(v);
        }
    }
    return result;
}

"""Filter neighbors of a UUID using pre-built adjacency and type maps.

Uses adj_map for O(1) neighbor lookup instead of scanning the full edge
list.  Accepts pre-computed applicable_visits and reverse_type_map to
avoid redundant work across BFS iterations.
"""
@ classmethod
impl JacTTGGenerator.filter_neighbors(
    cls: type[JacTTGGenerator],
    nd_id: UUID,
    applicable_visits: list,
    adj_map: dict[(UUID, list[tuple[(UUID, UUID)]])],
    type_map: dict[(UUID, type)],
    reverse_type_map: dict[(str, type)]
) -> list[tuple[(UUID, UUID)]] {
    edges_out = adj_map.get(nd_id);
    if not edges_out {
        return [];
    }
    filtered: list[tuple[(UUID, UUID)]] = [];
    seen_targets: set[UUID] = `set();
    for (eid, tgt) in edges_out {
        for v in applicable_visits {
            if isinstance(v, VisitType) {
                etype = type_map.get(eid);
                resolved_edge = cls._resolve_type(v.edge_type, reverse_type_map);
                if (
                    v.edge_type is None
                    or resolved_edge is None
                    or (etype is not None and issubclass(etype, resolved_edge))
                ) {
                    if (tgt not in seen_targets) {
                        filtered.append((eid, tgt));
                        seen_targets.add(tgt);
                    }
                }
            } else {
                # Non-VisitType entry (fallback: accept all).
                if (tgt not in seen_targets) {
                    filtered.append((eid, tgt));
                    seen_targets.add(tgt);
                }
            }
        }
    }
    return filtered;
}

"""Build a temporal trace graph from Root topology data.

Optimized BFS: builds an adjacency map and reverse type map once
upfront, uses collections.deque for O(1) popleft, and pre-filters
visit types per node to avoid redundant type resolution.
"""
@ classmethod
impl JacTTGGenerator.get_ttg(
    cls: type[JacTTGGenerator],
    warch: Any,
    start_id: UUID,
    graph: list[tuple[(UUID, UUID, UUID)]],
    type_map: dict[(UUID, type)]
) -> tuple[(TypedWalkerState, set[UUID], dict[(UUID, list[tuple[(UUID, UUID)]])])] {
    wtype_name = `type(warch).__name__;
    visits = getattr(warch, '__jac_ttg_visits__', []);

    # Build adjacency map once: src_uuid -> [(edge_uuid, tgt_uuid), ...]
    adj_map: dict[(UUID, list[tuple[(UUID, UUID)]])] = {};
    for (src, eid, tgt) in graph {
        adj_map.setdefault(src, []).append((eid, tgt));
    }

    # Build reverse type map once: type_name -> type
    reverse_type_map: dict[(str, type)] = {t.__name__: t for t in type_map.values()};

    ttg_root = TypedWalkerState(
        walker_type=wtype_name, depth=0, nd=start_id, incoming_edge=None, children=[]
    );
    queue = deque([ttg_root]);
    visited_ids: set[UUID] = `set();
    child_map: dict[(UUID, list[tuple[(UUID, UUID)]])] = {};

    while queue {
        state = queue.popleft();
        cur = state.nd;
        # Pre-filter visits for this node's type.
        nd_type = type_map.get(cur);
        app_visits = cls._applicable_visits(nd_type, visits, reverse_type_map);
        neighbors = cls.filter_neighbors(cur, app_visits, adj_map, type_map, reverse_type_map);
        for (eid, tgt) in neighbors {
            if (tgt in visited_ids) {
                continue;
            }
            visited_ids.add(tgt);
            child_map.setdefault(cur, []).append((eid, tgt));
            child_state = TypedWalkerState(
                walker_type=wtype_name,
                nd=tgt,
                depth=state.depth + 1,
                incoming_edge=eid,
                children=[]
            );
            state.children.append(child_state);
            queue.append(child_state);
        }
    }
    return (ttg_root, visited_ids, child_map);
}

"""Build a prefetch list from TTG child_map.

BFS traversal of the child_map using deque for O(1) popleft.
Produces an ordered list of UUIDs (edges + targets) for cache
prefetching.
"""
@ classmethod
impl JacTTGGenerator.get_prefetch_list(
    cls: type[JacTTGGenerator],
    start: UUID,
    ttg_children: dict[(UUID, list[tuple[(UUID, UUID)]])]
) -> list[UUID] {
    prefetch: list[UUID] = [];
    max_length = int(os.getenv('JAC_TTG_PREFETCH_LIMIT', '200'));
    seen: set[UUID] = `set();
    queue = deque([(None, start)]);
    while queue {
        (eid, nid) = queue.popleft();
        if (eid is not None and eid not in seen) {
            seen.add(eid);
            prefetch.append(eid);
        }
        if (nid not in seen) {
            seen.add(nid);
            prefetch.append(nid);
        }
        children = ttg_children.get(nid, []);
        for (child_eid, child_nid) in children {
            if (child_nid not in seen) {
                queue.append((child_eid, child_nid));
            }
        }
        if (len(prefetch) >= max_length) {
            break;
        }
    }
    return prefetch[:max_length];
}
