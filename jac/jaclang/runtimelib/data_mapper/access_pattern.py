"""Generate Access pattern graph."""

from dataclasses import dataclass

import jaclang.compiler.unitree as uni

import networkx as nx

from .visit_sequence import VisitInfo, get_walker_info


@dataclass
class WalkerState:
    """Store the walker state."""

    container: list[int]
    path: list[int]


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
    new_path: list[int] = state.path.copy()
    node = new_container.pop(0)
    visits = [visit for visit in visits if visit.async_edge is False]
    for visit in visits:
        filtered_neighbors = filter_neighbors(node, network, visit)
        new_container.extend(
            filtered_neighbors
        )  # TODO: Insert one by one with regard to the visit index.

    return WalkerState(
        container=new_container,
        path=new_path + [node],
    )


def get_access_pattern_single_walker(
    start_idx: int, network: nx.DiGraph, walker_type: uni.Archetype
) -> list[list[int]]:
    """Get the access pattern for a single walker spawn."""
    active_state_set: list[WalkerState] = [WalkerState(container=[start_idx], path=[])]
    visit_sequences = get_walker_info(walker_type)
    paths: list[list[int]] = []
    cnt = 0
    while len(active_state_set) > 0 and cnt < 100000:
        cnt += 1
        state = active_state_set.pop(0)
        node = state.container[0]
        node_type = network.nodes[node].get("node_type")
        new_state_set = [
            exec_sync_visit_sequence(state, network, visit_sequence)
            for visit_sequence in visit_sequences[node_type]
        ]
        if len(new_state_set) == 0:
            # If no new states generated, finalize the path
            state.path.append(node)
            paths.append(state.path)
            continue
        for new_state in new_state_set:
            if len(new_state.container) > 0:
                active_state_set.append(new_state)
            else:
                # If no more nodes to visit, finalize the path
                state.path.append(node)
                paths.append(state.path)
    # Finalize all remaining paths
    for state in active_state_set:
        state.path.append(state.container[0])
        paths.append(state.path)
    # print(paths)
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
