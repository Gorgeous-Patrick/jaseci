"""Implementation for TTG Generator constructs."""

import from jaclang.jac0core.archetype { VisitType }

"""Resolve a VisitType field (type or string name) to a type name string."""
@ classmethod
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

"""Build a temporal trace graph using TopologyIndex.

Uses the TopologyIndex's resolve_chain() to walk the adjacency list
with type-only filters for each visit type. BFS expansion from start_id.
"""
@ classmethod
impl JacTTGGenerator.get_ttg(
    cls: type[JacTTGGenerator], warch: Any, start_id: UUID, topology_index: Any
) -> tuple {
    wtype_name = `type(warch).__name__;
    visits = getattr(warch, '__jac_ttg_visits__', []);
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
@ classmethod
impl JacTTGGenerator.get_prefetch_list(
    cls: type[JacTTGGenerator], start: UUID, ttg_children: dict
) -> list[UUID] {
    prefetch: list[UUID] = [];
    max_length = int(os.getenv('JAC_TTG_PREFETCH_LIMIT', '200'));
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
