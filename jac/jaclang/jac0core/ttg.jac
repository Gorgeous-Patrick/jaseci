"""TTG (Temporal Trace Graph) Generator.

Predicts walker traversal paths by analyzing Root's topology graph
(list of edge tuples) and type_map (UUID -> type mapping). This approach
avoids loading any Jac archetype instances, operating purely on UUIDs
and type metadata stored in Root.
"""
import os;
import from collections { deque }
import from dataclasses { dataclass, field }
import from uuid { UUID }
import from typing { Any }
import from jaclang.jac0core.archetype { VisitType }

"""State entry in the temporal trace graph."""
@dataclass
class TypedWalkerState {
    has walker_type: str,
        nd: UUID,
        depth: int,
        incoming_edge: (UUID | None) = None,
        children: list[TypedWalkerState] = field(default_factory=`list);
}

"""TTG Generator — predicts traversal paths from Root's topology data.

All methods are classmethods operating on Root.graph and Root.type_map.
No Jac archetype instances are loaded or populated.
"""
class JacTTGGenerator {
    """Resolve a VisitType field (type or string name) to a concrete type.

    Returns None if unresolved.
    """
    @classmethod
    def _resolve_type(
        cls: type[JacTTGGenerator],
        ref: (type | str | None),
        reverse_type_map: dict[(str, type)]
    ) -> (type | None);

    """Filter neighbors of a UUID using pre-built adjacency and type maps.

    Returns list of (edge_uuid, target_uuid) pairs that match the
    walker's visit type constraints.  Accepts pre-built structures to
    avoid redundant computation across BFS iterations.
    """
    @classmethod
    def filter_neighbors(
        cls: type[JacTTGGenerator],
        nd_id: UUID,
        applicable_visits: list,
        adj_map: dict[(UUID, list[tuple[(UUID, UUID)]])],
        type_map: dict[(UUID, type)],
        reverse_type_map: dict[(str, type)]
    ) -> list[tuple[(UUID, UUID)]];

    """Pre-filter walker visits applicable to a given node type.

    Returns the subset of visits whose from_node_type constraint is
    satisfied by nd_type.  Called once per BFS node instead of once per
    edge.
    """
    @classmethod
    def _applicable_visits(
        cls: type[JacTTGGenerator],
        nd_type: (type | None),
        visits: list,
        reverse_type_map: dict[(str, type)]
    ) -> list;

    """Build a temporal trace graph rooted at start_id.

    Returns (root_state, visited_ids, child_map) where:
    - root_state: TypedWalkerState tree
    - visited_ids: set of all visited UUIDs
    - child_map: dict mapping UUID -> list of (edge_uuid, target_uuid)
    """
    @classmethod
    def get_ttg(
        cls: type[JacTTGGenerator],
        warch: Any,
        start_id: UUID,
        graph: list[tuple[(UUID, UUID, UUID)]],
        type_map: dict[(UUID, type)]
    ) -> tuple[(TypedWalkerState, set[UUID], dict[(UUID, list[tuple[(UUID, UUID)]])])];

    """Build a prefetch list from a TTG child_map.

    Returns an ordered list of UUIDs to prefetch, respecting the
    JAC_TTG_PREFETCH_LIMIT environment variable.
    """
    @classmethod
    def get_prefetch_list(
        cls: type[JacTTGGenerator],
        start: UUID,
        ttg_children: dict[(UUID, list[tuple[(UUID, UUID)]])]
    ) -> list[UUID];
}
