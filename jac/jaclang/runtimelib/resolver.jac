"""Per-hop edge-traversal resolver.

The runtime entry point `refs()` walks an `ObjectSpatialPath` by folding over
the chain of hops. Each hop is resolved by a single, uniform `resolve_hop`
call — the same function for every position. The intent is to remove the
all-or-nothing split between `planner.execute_path` (which returned `None`
for the whole query whenever any one hop tripped a limitation) and the slow
`edges_to_nodes` loop, so that future PRs can convert each per-hop bail into
a local routing branch.

This module replaces `planner.execute_path` as the fast-path entry called
from `refs()`. Its public contract matches `execute_path` exactly: returns a
list of `NodeAnchor` when a fast path applies, `None` to signal "fall through
to the slow edge-walk." Behavior is parity with today's planner — the 12 bail
conditions from `execute_path` are preserved, just enforced per-hop instead
of as a single up-front strategy decision.

Position-aware concerns (which hop receives `slc`, whether the
canonical-edge-walk order is required for an unsliced single-hop call, the
foreign-root parity guard) live in `resolve_path_anchors`. `resolve_hop`
itself is uniform.
"""

import os;
import logging;
import from uuid { UUID }

import from jaclang.jac0core.archetype { Anchor, NodeAnchor }
import from jaclang.runtimelib.query_plan { QueryPlan, HopSpec }

glob logger = logging.getLogger(__name__),
     __all__ = ['ChainHop', 'resolve_hop', 'resolve_path_anchors'];


"""One hop's data, carrying both the type names the topology_index consumes
and the raw `ObjectSpatialDestination` whose callable filters the slow path
needs. Two views of the same hop fused into one struct so the per-hop fold
has a single parameter shape regardless of which dispatch fires."""
obj ChainHop {
    has edge_type: (str | None) = None,
        node_type: (str | None) = None,
        direction: int = 2,
        dest: any = None;
}


"""Resolve a single hop on the topology_index. Returns a `set[UUID]` of
target node IDs when `slc is None` (the intermediate case), or a `list[UUID]`
already sliced in canonical edge-walk order when `slc is not None`.

Returns `None` when the index can't resolve this hop (no usable index, or
the hop carries no useful filter and the legacy bail applies). The caller
decides whether to fall through.
"""
def resolve_hop(
    mem: any,
    current_ids: any,
    hop: ChainHop,
    root_anchor: any,
    hop_idx: int,
    slc: (slice | None) = None
) -> (any);


"""High-level path entry point. Walks the path's hop chain via the per-hop
`resolve_hop` fold and returns materialized `NodeAnchor`s.

Returns `None` to signal "fall through to the legacy edge-walk in `refs()`"
— identical contract to `planner.execute_path`. This PR preserves all 12 of
`execute_path`'s bail conditions; follow-ups will widen the coverage.
"""
def resolve_path_anchors(
    mem: any, path: any, slc: (slice | None) = None
) -> (list[any] | None);
