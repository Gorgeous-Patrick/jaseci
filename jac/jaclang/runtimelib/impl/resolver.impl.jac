"""Per-hop resolver implementation."""

import inspect;
import dis;
import from typing { cast }


"""Truthy `JAC_QUERY_TRACE` toggles per-hop strategy logging."""
def _trace_enabled -> bool {
    val = os.environ.get('JAC_QUERY_TRACE', '');
    return val.lower() in ('1', 'true', 'yes', 'on');
}


"""Inspect a Jac-emitted filter lambda for archetype-type identity.

Returns the archetype class name if the lambda is a pure `isinstance(i, T)`
check (or an Archetype instance acting as an identity filter). Returns None
when the filter is None or non-trivial.
"""
def _filter_type_name(filt: (Callable[[Archetype], bool] | None)) -> (str | None) {
    if filt is None {
        return None;
    }
    try {
        if isinstance(filt, Archetype) {
            return `type(filt).__name__;
        }
    } except Exception {
        ;
    }
    try {
        closure = inspect.getclosurevars(filt);
        for val in `list(closure.nonlocals.values()) + `list(
            closure.globals.values()
        ) {
            if isinstance(val, `type) and issubclass(val, Archetype) {
                return val.__name__;
            }
        }
    } except Exception {
        ;
    }
    return None;
}


"""Detect whether a filter lambda contains predicate ops beyond type checks.

Pure `isinstance(i, T)` checks compile to LOAD_GLOBAL + CALL_FUNCTION +
RETURN; predicates introduce LOAD_ATTR / COMPARE_OP / CONTAINS_OP / IS_OP.
Conservative on inspection failure — assume predicates present so we never
silently skip filtering.
"""
def _filter_has_predicates(filt: (Callable[[Archetype], bool] | None)) -> bool {
    if filt is None {
        return False;
    }
    try {
        opcodes = {instr.opname for instr in dis.get_instructions(filt)};
    } except (TypeError, AttributeError, ValueError) {
        return True;
    }
    return bool(opcodes & {'LOAD_ATTR', 'COMPARE_OP', 'CONTAINS_OP', 'IS_OP'});
}


"""Emit a single per-hop trace line. No-op when JAC_QUERY_TRACE is off."""
def _trace_hop(
    strategy: str,
    hop_idx: int,
    in_count: int,
    out_count: int,
    hop: ChainHop,
    extra: str = ''
) -> None {
    if not _trace_enabled() {
        return;
    }
    edge_label = hop.edge_type or '*';
    node_label = hop.node_type or '*';
    suffix = f" {extra}" if extra else '';
    logger.info(
        f"[query] hop[{hop_idx}]:{strategy} edge={edge_label} node={node_label}"
        f" dir={hop.direction} in={in_count} out={out_count}{suffix}"
    );
}


"""Emit a final-step trace line for materialization decisions. The fold itself
is logged per-hop; this captures the post-fold step (pushdown vs. batch_get)
so the JAC_QUERY_TRACE output describes the whole call."""
def _trace_final(strategy: str, narrowed: int, extra: str = '') -> None {
    if not _trace_enabled() {
        return;
    }
    suffix = f" {extra}" if extra else '';
    logger.info(f"[query] final:{strategy} narrowed={narrowed}{suffix}");
}


"""Materialize a set of UUIDs to NodeAnchors via `batch_get`, applying
optional post_filter and slice."""
def _materialize_ids(
    mem: Memory,
    ids: list[UUID],
    post_filter: (Callable[[Archetype], bool] | None) = None,
    slc: (slice | None) = None
) -> list[NodeAnchor] {
    if not ids {
        return [];
    }
    import from jaclang.runtimelib.memory { TieredMemory }
    loaded: dict[UUID, Anchor];
    if isinstance(mem, TieredMemory) {
        loaded = mem.batch_get(ids);
    } else {
        loaded = {
            i: a
            for i in ids
            if (a := mem.get(i)) is not None
        };
    }
    result: list[NodeAnchor] = [];
    for i in ids {
        anchor = loaded.get(i);
        if isinstance(anchor, NodeAnchor) and anchor.archetype {
            if post_filter is not None and not post_filter(anchor.archetype) {
                continue;
            }
            result.append(anchor);
        }
    }
    if slc is not None {
        result = result[slc];
    }
    return result;
}


"""Backend pushdown: hand a reduced plan to `mem.execute_plan` and apply the
post_filter / slice fallback locally when capabilities don't cover them.

Plans built by `resolve_path_anchors` are node-resolving (chain consumed,
`id_in` carries node IDs); backends yield `NodeAnchor` for that shape."""
def _try_pushdown(mem: Memory, plan: QueryPlan) -> list[NodeAnchor] {
    result: list[NodeAnchor] = [];
    for anchor in mem.execute_plan(plan) {
        if (
            plan.post_filter is not None
            and anchor.archetype is not None
            and not plan.post_filter(anchor.archetype)
        ) {
            continue;
        }
        result.append(cast(NodeAnchor, anchor));
    }
    if plan.slc is not None and 'slice' not in mem.capabilities() {
        result = result[plan.slc];
    }
    return result;
}


"""Resolve the root anchor that owns an ObjectSpatialPath's origin. Returns
None when the origin isn't persistent or its owning root can't be found."""
def _path_root_anchor(mem: Memory, path: ObjectSpatialPath) -> (NodeAnchor | None) {
    if not path.origin {
        return None;
    }
    origin_anchor = path.origin[0].__jac__;
    if not origin_anchor.persistent {
        return None;
    }
    import from jaclang.jac0core.archetype { Root }
    if origin_anchor.root is None {
        if isinstance(origin_anchor, NodeAnchor)
        and isinstance(origin_anchor.archetype, Root) {
            return origin_anchor;
        }
        return None;
    }
    try {
        `root = mem.get(origin_anchor.root);
        if isinstance(`root, NodeAnchor) {
            return `root;
        }
    } except Exception {
        ;
    }
    return None;
}


"""Build a `list[ChainHop]` from the path. Mirrors today's
`planner._build_plan_from_path` bail logic so the resolver's bail surface is
identical to `execute_path`'s.

Returns None when:
  * `path.origin` is empty
  * the origin's anchor is not persistent
  * `path.edge_only=True` and there are no prefix destinations left
  * any non-final hop has predicate edge or node filters
  * the final hop has predicate edge filters
  * the chain has no useful filter anywhere AND no final post_filter
    (natural edge-walk is optimal, no point engaging the index)
"""
def _build_hops(path: ObjectSpatialPath) -> (list[ChainHop] | None) {
    if not path.origin {
        return None;
    }
    origin_anchor = path.origin[0].__jac__;
    if not origin_anchor.persistent {
        return None;
    }
    destinations = path.destinations[:-1] if path.edge_only else path.destinations;
    if not destinations {
        return None;
    }
    chain: list[ChainHop] = [];
    last_idx = len(destinations) - 1;
    has_filter = False;
    last_has_post_filter = False;
    for (i, dest) in enumerate(destinations) {
        if _filter_has_predicates(dest.`edge) {
            return None;
        }
        node_has_pred = _filter_has_predicates(dest.nd);
        if i != last_idx and node_has_pred {
            return None;
        }
        edge_type = _filter_type_name(dest.`edge);
        node_type = _filter_type_name(dest.nd);
        chain.append(
            ChainHop(
                edge_type=edge_type,
                node_type=node_type,
                direction=dest.direction.value,
                dest=dest,
            )
        );
        if edge_type is not None or node_type is not None {
            has_filter = True;
        }
        if i == last_idx and node_has_pred {
            last_has_post_filter = True;
        }
    }
    if not has_filter and not last_has_post_filter {
        return None;
    }
    return chain;
}


"""Foreign-root parity guard. Returns True if any ID in `ids` belongs to a
root other than `root_anchor.id`.

This preserves today's `bail_on_intermediate_foreign=True` semantics without
the resolver itself having to know its position. `_resolve_prefix` calls this
after every intermediate hop; if it returns True, the prefix walker bails to
None so `refs()` falls through to the slow loop (which crosses roots
transparently via `nanch.edges`).

Implementation: walks each ID via `mem.get` and reads `.root`. Cheap for
typical L1-cached anchors, and we only run it after a hop has narrowed to a
small candidate set. Future PR: swap for `TopologyIndex.get_cross_root_ids`
or `has_foreign` to avoid the per-ID fetch for large sets.
"""
def _has_foreign(mem: Memory, ids: set[UUID], root_anchor: NodeAnchor) -> bool {
    for uid in ids {
        try {
            anchor = mem.get(uid);
        } except Exception {
            continue;
        }
        if not isinstance(anchor, NodeAnchor) {
            continue;
        }
        if anchor.root is None {
            if anchor.id != root_anchor.id {
                return True;
            }
        } elif anchor.root != root_anchor.id {
            return True;
        }
    }
    return False;
}


"""Walk the chain prefix with the foreign-root parity guard interleaved.

Each hop calls the uniform `resolve_hop` with `slc=None`; between hops the
guard fires and bails the whole walk if the intermediate output crosses
roots. This is the position-aware part of the fold — `resolve_hop` itself
stays uniform.
"""
def _resolve_prefix(
    mem: Memory, ids: set[UUID], prefix_hops: list[ChainHop], root_anchor: NodeAnchor
) -> (set[UUID] | None) {
    current: set[UUID] = ids;
    for (i, hop) in enumerate(prefix_hops) {
        next_ids = resolve_hop(mem, current, hop, root_anchor, i, slc=None);
        if next_ids is None or isinstance(next_ids, list) {
            return None;
        }
        if _has_foreign(mem, next_ids, root_anchor) {
            return None;
        }
        current = next_ids;
    }
    return current;
}


impl resolve_hop(
    mem: Memory,
    current_ids: set[UUID],
    hop: ChainHop,
    root_anchor: NodeAnchor,
    hop_idx: int,
    slc: (slice | None) = None
) -> (set[UUID] | list[UUID] | None) {
    # NB: "no useful filter" is a *chain-level* property, enforced once by
    # `_build_hops` before the fold even starts. Individual hops in the middle
    # of a chain may legitimately carry no type filter (e.g. `r --> --> leaf`),
    # and the topology index handles those by matching every edge in the given
    # direction. Bailing per-hop here would force the slow loop for any chain
    # with an unfiltered intermediate hop — exactly what `plan_chain_ordered`
    # avoided by walking the chain in one call.
    import from jaclang.runtimelib.topology_index { TopologyIndex }
    idx = root_anchor.get_topology_index();
    if not isinstance(idx, TopologyIndex) or len(idx) == 0 {
        return None;
    }
    in_count = len(current_ids);
    if slc is not None {
        ordered = idx.resolve_chain_ordered(
            current_ids, hop.edge_type, hop.node_type, hop.direction, slc
        );
        _trace_hop(
            'index:ordered',
            hop_idx,
            in_count,
            len(ordered),
            hop,
            f"slc={slc.start}:{slc.stop}"
        );
        return ordered;
    }
    triple = (hop.edge_type, hop.node_type, hop.direction);
    narrowed = idx.resolve_chain(current_ids, [triple]);
    if narrowed is None {
        return None;
    }
    _trace_hop('index:set', hop_idx, in_count, len(narrowed), hop);
    return narrowed;
}


"""High-level path entry. Position-aware glue around the uniform `resolve_hop`:

  1. `_build_hops` runs all path-shape bails (origin, persistence, predicate
     filters, no-useful-filter).
  2. `_path_root_anchor` resolves the owning root or bails.
  3. The fold walks `chain[:-1]` via `_resolve_prefix` (with foreign-root
     parity guard between hops).
  4. The last hop runs `resolve_hop` with `effective_slc` set per today's
     `use_ordered` policy.
  5. Materialization: ordered results go straight to `_materialize_ids`;
     set results try backend pushdown first (matches today's set-narrowing
     branch — needed for parity on Mongo's `id_in + type_pushdown` queries
     even when the user didn't pass a slice).
"""
impl resolve_path_anchors(
    mem: Memory, path: ObjectSpatialPath, slc: (slice | None) = None
) -> (list[NodeAnchor] | None) {
    chain = _build_hops(path);
    if chain is None {
        return None;
    }
    root_anchor = _path_root_anchor(mem, path);
    if root_anchor is None {
        return None;
    }
    current: set[UUID] = {cast(UUID, nd.__jac__.id) for nd in path.origin};
    if len(chain) > 1 {
        prefix = _resolve_prefix(mem, current, chain[:-1], root_anchor);
        if prefix is None {
            return None;
        }
        current = prefix;
    }
    last_hop = chain[-1];
    last_has_post_filter = _filter_has_predicates(last_hop.dest.nd);
    post_filter: (Callable[[Archetype], bool] | None) = (
        last_hop.dest.node_filter if last_has_post_filter else None
    );
    use_ordered = (not last_has_post_filter) and (slc is not None or len(chain) == 1);
    effective_slc: (slice | None) = None;
    if use_ordered {
        effective_slc = slc if slc is not None else slice(None, None, None);
    }
    result = resolve_hop(
        mem, current, last_hop, root_anchor, len(chain) - 1, effective_slc
    );
    if result is None {
        return None;
    }
    if isinstance(result, list) {
        return _materialize_ids(mem, result);
    }
    # Set narrowing → try backend pushdown for parity with today's behavior.
    plan = QueryPlan(
        root_id=root_anchor.id,
        chain=[],
        id_in=result,
        node_type_final=last_hop.node_type,
        slc=slc,
        post_filter=post_filter,
    );
    if plan.needs() <= mem.capabilities() {
        _trace_final('pushdown', len(result));
        return _try_pushdown(mem, plan);
    }
    _trace_final('floor', len(result));
    return _materialize_ids(mem, list(result), post_filter=post_filter, slc=slc);
}
