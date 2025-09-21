"""Generate Access pattern graph."""

from dataclasses import dataclass
from hmac import new

import jaclang.compiler.unitree as uni

from jaclang.runtimelib.temporal_trace_graph.ttg_node import TTG_Node, print_ttg, print_ttg_simple
import networkx as nx

from ..data_mapper.visit_sequence import VisitInfo, get_walker_info


@dataclass
class WalkerState:
    """Store the walker state."""

    container: list[int]
    # path: list[int]
    ttg_node: TTG_Node


def filter_neighbors(node_idx: int, network: nx.DiGraph, visit: VisitInfo) -> list[int]:
    """Filter neighbors based on visit info and walker type."""
    filtered_neighbors = []

    # Get all neighbors
    for neighbor_idx in network.neighbors(node_idx):
        # Get edge data between current node and neighbor
        edge_data = network.get_edge_data(node_idx, neighbor_idx)
        if edge_data is None:
            continue
        edge_type = edge_data.get("edge_type")

        if visit.edge_type is None or visit.edge_type == edge_type:
            filtered_neighbors.append(neighbor_idx)

    return filtered_neighbors


def exec_sync_visit_sequence(
    state: WalkerState, network: nx.DiGraph, visits: list[VisitInfo]
) -> WalkerState:
    """Execute the visit sequence to get the access pattern."""
    new_container: list[int] = state.container.copy()
    # new_path: list[int] = state.path.copy()
    node = new_container.pop(0)
    visits = [visit for visit in visits if visit.async_edge is False]
    for visit in visits:
        filtered_neighbors = filter_neighbors(node, network, visit)
        new_container.extend(
            filtered_neighbors
        )  # TODO: Insert one by one with regard to the visit index.
        # print(f"At node {node}, going to {filtered_neighbors} with visit {visit}")

    new_ttg_node = TTG_Node(
        idx=new_container[0] if len(new_container) > 0 else None, conditional_next_nodes=[], parallel_next_nodes=[]
    )

    return WalkerState(
        container=new_container,
        ttg_node=new_ttg_node,
    )


def get_access_pattern_single_walker(
    start_idx: int, network: nx.DiGraph, walker_type: uni.Archetype, target_node_cnt: int = 100000
) -> TTG_Node:
    """Get the access pattern for a single walker spawn."""
    root_ttg_node = TTG_Node(
        idx=start_idx, conditional_next_nodes=[], parallel_next_nodes=[]
    )
    active_state_set: list[WalkerState] = [WalkerState(container=[start_idx], ttg_node=root_ttg_node)]
    visit_sequences = get_walker_info(walker_type)
    # paths: list[list[int]] = []
    cnt = 0
    while len(active_state_set) > 0 and cnt < target_node_cnt:
        cnt += 1
        state = active_state_set.pop(0)
        node = state.container[0]
        node_type = network.nodes[node].get("node_type")
        new_state_set = [
            exec_sync_visit_sequence(state, network, visit_sequence)
            for visit_sequence in visit_sequences[node_type]
        ]
        state.ttg_node.conditional_next_nodes = [new_state.ttg_node for new_state in new_state_set]
        for new_state in new_state_set:
            if len(new_state.container) > 0 and new_state.container[0] is not None:
                active_state_set.append(new_state)

        # print(f"Going from {node} to {[new_state.ttg_node.idx for new_state in new_state_set]}")
    return root_ttg_node

def get_paths_from_ttg(ttg_node: TTG_Node, current_path: list[int] | None = None) -> list[list[int]]:
    """Extract all paths from the TTG."""
    if current_path is None:
        current_path = []
    if ttg_node.conditional_next_nodes == []:
        return [current_path.copy()]
    assert ttg_node.idx is not None
    current_path.append(ttg_node.idx)
    paths = []
    for next_node in ttg_node.conditional_next_nodes:
        paths.extend(get_paths_from_ttg(next_node, current_path))
    for next_node in ttg_node.parallel_next_nodes:
        paths.extend(get_paths_from_ttg(next_node, current_path))
    current_path.pop()
    return paths


def get_access_pattern(network: nx.DiGraph, paths: list[list[int]]) -> nx.DiGraph:
    """Calculate edge weights based on path traversal frequency."""
    # Create a copy of the network and clear all existing edges
    weighted_network = network.copy()
    weighted_network.clear_edges()

    for path in paths:

        edges = [(path[i], path[i + 1]) for i in range(len(path) - 1)]

        # Add edges with their calculated weights
        for idx, (from_node, to_node) in enumerate(edges):
            attr = weighted_network.get_edge_data(from_node, to_node)
            if attr is None:
                attr = {"label": []}
            label = attr.get("label", [])
            label.append(idx)
            weighted_network.add_edge(from_node, to_node, label=label)

    return weighted_network
