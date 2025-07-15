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
    # print(f"Unfiltered neighbor num: {len(list(network.neighbors(node_idx)))}")
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
    while True:
        print(
            f"{node.unparse()} --> len: {len(node.bb_out)}: {[code.unparse() for code in node.bb_out]}"
        )
        if isinstance(node, uni.VisitStmt):
            visit_restriction = get_visit_restriction_of_single_visit(node)
            # print(f"Visit Restriction: {visit_restriction}")
            neighbors = filter_neighbors(start_idx, network, visit_restriction)
            # print(f"Neighbor Num: {len(neighbors)}")
            sym_visit = (visit_restriction.index, neighbors)
            res = [visits + [sym_visit] for visits in res]
        if node is bb_tail:
            break
        else:
            node = node.bb_out[0]

    print("End of BB")
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
    loc: int | None

    def _new_possible_state(
        self, possible_visit: SymbolicVisits
    ) -> "SymbolicWalkerState":
        container = self.container.copy()
        for visit in possible_visit:
            insert_loc = visit[0]
            if insert_loc < -len(container):
                insert_loc = 0
            elif insert_loc < 0:
                insert_loc += len(container) + 1
            container = container[:insert_loc] + visit[1] + container[insert_loc:]
        if len(container) > 0:
            loc = container.pop(0)
        else:
            loc = None
        return SymbolicWalkerState(container=container, loc=loc)

    def new_possible_states(
        self, possible_visits: SymbolicVisitPossibilities
    ) -> list["SymbolicWalkerState"]:
        """Generate a list of new possible states after each run."""
        return [
            self._new_possible_state(possible_visit)
            for possible_visit in possible_visits
        ]


def get_next_possible_visits(
    state: SymbolicWalkerState, flows: dict[str, uni.Ability], network: nx.DiGraph
) -> SymbolicVisitPossibilities:
    """Get the list of all possible next states."""
    flow = flows[network.nodes[state.loc]["node_type"]]
    assert state.loc is not None
    possible_visits = get_access_pattern_single_walker_one_run(
        state.loc, network, flow, [[]]
    )
    return possible_visits
    # return state.new_possible_states(possible_visits)


def get_access_pattern_single_walker(
    start_idx: int, network: nx.DiGraph, walker: uni.Archetype
) -> None:
    """Iterate multiple times."""
    possible_states: list[SymbolicWalkerState] = [
        SymbolicWalkerState(container=[], loc=start_idx)
    ]

    abilities = walker.get_all_sub_nodes(uni.Ability)
    flows = {
        ability.get_all_sub_nodes(uni.EventSignature)[0]
        .get_all_sub_nodes(uni.Name)[0]
        .value: ability
        for ability in abilities
    }
    for i in range(100):
        print(f"Iteration: {i}")
        new_possible_states: list[SymbolicWalkerState] = []
        # print(len(possible_states))
        for possible_state in possible_states:
            possible_visits = get_next_possible_visits(possible_state, flows, network)
            print(f"Possibilities: {possible_visits}")
            new_possible_states = (
                new_possible_states
                + possible_state.new_possible_states(possible_visits)
            )
        possible_states = [
            state for state in new_possible_states if state.loc is not None
        ]
