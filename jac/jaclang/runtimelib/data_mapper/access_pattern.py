"""Generate Access pattern graph."""

from dataclasses import dataclass
from typing import TypeAlias

import jaclang.compiler.unitree as uni

import networkx as nx

from .visit_restrictions import VisitRestriction, get_visit_restriction_of_single_visit


def filter_neighbors(
    node_idx: int, network: nx.DiGraph, visit_restrictions: VisitRestriction
) -> list[int]:
    """Filter neighbors based on visit info and walker type."""
    filtered_neighbors = []

    # Get all neighbors
    for neighbor_idx in network.neighbors(node_idx):
        # Get edge data between current node and neighbor
        edge_data = network.get_edge_data(node_idx, neighbor_idx)
        if edge_data is None:
            continue
        edge_type = edge_data.get("edge_type")

        # If no specific edge type is required or edge type matches
        if (
            visit_restrictions.edge_type is None
            or visit_restrictions.edge_type == edge_type
        ):
            filtered_neighbors.append(neighbor_idx)
            break  # Found a match, no need to check other visits

    return filtered_neighbors


SymbolicVisit: TypeAlias = tuple[int, list[int]]
SymbolicVisits: TypeAlias = list[SymbolicVisit]
SymbolicVisitPossibilities: TypeAlias = list[SymbolicVisits]


def get_access_pattern_single_walker_one_run(
    start_idx: int,
    network: nx.DiGraph,
    start_node: uni.UniCFGNode,
    possibilities: SymbolicVisitPossibilities,
) -> SymbolicVisitPossibilities:
    """Get all the possible combinations of visit statements in one run."""
    res = possibilities.copy()
    bb_tail = start_node.get_tail()
    node = start_node
    while not (node is bb_tail):
        if isinstance(node, uni.VisitStmt):
            visit_restriction = get_visit_restriction_of_single_visit(node)
            neighbors = filter_neighbors(start_idx, network, visit_restriction)
            sym_visit = (visit_restriction.index, neighbors)
            res = [visits + [sym_visit] for visits in res]
        node = node.bb_out[0]

    if len(node.bb_out) == 0:
        return res
    accumulated: SymbolicVisitPossibilities = []
    for next_node in node.bb_out:
        accumulated.extend(
            get_access_pattern_single_walker_one_run(start_idx, network, next_node, res)
        )

    return accumulated


@dataclass
class SymbolicWalkerState:
    """Simplified walker state."""

    container: list[int]
    loc: int

    def _new_possible_state(
        self, possible_visit: SymbolicVisits
    ) -> "SymbolicWalkerState":
        container = self.container.copy()
        loc = container.pop(0)
        for visit in possible_visit:
            insert_loc = visit[0]
            if insert_loc < -len(container):
                insert_loc = 0
            elif insert_loc < 0:
                insert_loc += len(container) + 1
            container = container[:insert_loc] + visit[1] + container[insert_loc:]
        return SymbolicWalkerState(container=container, loc=loc)

    def new_possible_states(
        self, possible_visits: SymbolicVisitPossibilities
    ) -> list["SymbolicWalkerState"]:
        """Generate a list of new possible states after each run."""
        return [
            self._new_possible_state(possible_visit)
            for possible_visit in possible_visits
        ]


def get_next_possible_states(
    state: SymbolicWalkerState, flows: dict[str, uni.Ability], network: nx.DiGraph
) -> list[SymbolicWalkerState]:
    """Get the list of all possible next states."""
    flow = flows[network.nodes[state.loc]["node_type"]]
    possible_visits = get_access_pattern_single_walker_one_run(
        state.loc, network, flow, [[]]
    )
    return state.new_possible_states(possible_visits)


def get_access_pattern_single_walker(
    start_idx: int, network: nx.DiGraph, flows: dict[str, uni.Ability]
) -> None:
    """Iterate multiple times."""
    possible_states: list[SymbolicWalkerState] = [
        SymbolicWalkerState(container=[], loc=start_idx)
    ]

    for _ in range(100):
        new_possible_states: list[SymbolicWalkerState] = []
        for possible_state in possible_states:
            new_possible_states = new_possible_states + get_next_possible_states(
                possible_state, flows, network
            )
            possible_states = new_possible_states
