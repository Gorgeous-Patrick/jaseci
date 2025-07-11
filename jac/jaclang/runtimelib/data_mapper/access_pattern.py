"""Generate Access pattern graph."""

from dataclasses import dataclass
from typing import TypeAlias
from jaclang.runtimelib.data_mapper.visit_restrictions import Block, VisitRestriction
import networkx as nx
import random

from .static_phase import VisitInfo


def filter_neighbors(
    node_idx: int, network: nx.DiGraph, visit_info: list[VisitInfo], walker_type: str
) -> list[int]:
    """Filter neighbors based on visit info and walker type."""
    filtered_neighbors = []

    # Get the node type of the current node
    current_node_type = network.nodes[node_idx].get("node_type")

    # Find matching visit info for this walker type and node type
    matching_visits = [
        visit
        for visit in visit_info
        if visit.walker_type == walker_type
        and visit.from_node_type == current_node_type
    ]

    # Get all neighbors
    for neighbor_idx in network.neighbors(node_idx):
        # Get edge data between current node and neighbor
        edge_data = network.get_edge_data(node_idx, neighbor_idx)
        if edge_data is None:
            continue
        edge_type = edge_data.get("edge_type")

        # Check if any visit info matches the edge type
        for visit in matching_visits:
            # If no specific edge type is required or edge type matches
            if visit.edge_type is None or visit.edge_type == edge_type:
                filtered_neighbors.append(neighbor_idx)
                break  # Found a match, no need to check other visits

    return filtered_neighbors

SymbolicVisit: TypeAlias = tuple[int, list[int]]
SymbolicVisits: TypeAlias = list[SymbolicVisit]
SymbolicVisitPossibilities: TypeAlias = list[SymbolicVisits]

def get_access_pattern_single_walker_one_run(start_idx, network: nx.DiGraph, flow: Block, possibilities: SymbolicVisitPossibilities) -> SymbolicVisitPossibilities:
    res = possibilities.copy()
    for step in flow:
        if isinstance(step, VisitRestriction):
            # If the step is a VisitRestriction, find neighbors matching the edge_type
            neighbors = []
            for neighbor_idx in network.neighbors(start_idx):
                edge_data = network.get_edge_data(start_idx, neighbor_idx)
                if edge_data is None:
                    continue
                edge_type = edge_data.get("edge_type")
                if step.edge_type is None or step.edge_type == edge_type:
                    neighbors.append(neighbor_idx)
            sym_visit = (step.index, neighbors)
            res = [visits + [sym_visit] for visits in res]

        # If it is a union type (i.e., tuple of Blocks), recursively process both branches and concatenate results
        elif isinstance(step, tuple) and len(step) == 2:
            left = get_access_pattern_single_walker_one_run(start_idx, network, step[0], res)
            right = get_access_pattern_single_walker_one_run(start_idx, network, step[1], res)
            res = left + right
        
    # Remove duplicates in res
    # Each element in res is a list of SymbolicVisit tuples; remove duplicate lists
    # We'll use tuple(map(tuple, ...)) to make lists hashable for set
    unique_res = []
    seen = set()
    for visits in res:
        key = tuple(visits)
        if key not in seen:
            unique_res.append(visits)
            seen.add(key)
    res = unique_res
    return res

@dataclass
class SymbolicWalkerState:
    container: list[int]
    loc: int
    def new_possible_state(self, possible_visit: SymbolicVisits) -> "SymbolicWalkerState":
        container = self.container.copy()
        loc = container.pop(0)
        for visit in possible_visit:
            insert_loc = visit[0]
            if insert_loc < -len(container):
                insert_loc = 0
            elif insert_loc < 0:
                insert_loc += len(container) + 1;
            container = container[:insert_loc] + visit[1] + container[insert_loc:]
        return SymbolicWalkerState(container= container, loc = loc)


    def new_possible_states(self, possible_visits: SymbolicVisitPossibilities) -> list["SymbolicWalkerState"]:
        return [self.new_possible_state(possible_visit) for possible_visit in possible_visits]

def get_next_possible_states(state: SymbolicWalkerState, flows: dict[str, Block], network: nx.DiGraph) -> list[SymbolicWalkerState]:
    flow = flows[network.nodes[state.loc]["node_type"]]
    possible_visits = get_access_pattern_single_walker_one_run(state.loc, network, flow, [[]])
    return state.new_possible_states(possible_visits)


def get_access_pattern_single_walker(start_idx: int, network: nx.DiGraph, flows: dict[str, Block]):
    possible_states: list[SymbolicWalkerState] = [SymbolicWalkerState(container=[], loc = start_idx)]
    
    for _ in range(100):
        new_possible_states : list[SymbolicWalkerState] = [];
        for possible_state in possible_states:
            new_possible_states = new_possible_states + get_next_possible_states(possible_state, flows, network)
            possible_states = new_possible_states

