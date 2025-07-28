"""Generate Access pattern graph."""

import networkx as nx

from .visit_sequence import VisitInfo


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


def get_access_pattern_single_walker(
    start_idx: int, network: nx.DiGraph, visit_info: list[VisitInfo], walker_type: str
) -> list[int]:
    """Get the access pattern for a single walker spawn."""
    container: list[int] = [start_idx]
    visited: set[int] = set()
    path: list[int] = []
    i = 0
    while len(container) > 0 and i < 10:
        i += 1
        top = container.pop(0)
        path.append(top)
        if top in visited:
            continue
        visited.add(top)
        filtered_neighbors = filter_neighbors(top, network, visit_info, walker_type)
        # random.shuffle(filtered_neighbors)
        for neighbor in filtered_neighbors:
            container.append(neighbor)
    return path


def get_access_pattern(network: nx.DiGraph, path: list[int]) -> nx.DiGraph:
    """Calculate edge weights based on path traversal frequency."""
    # Create a copy of the network and clear all existing edges
    weighted_network = network.copy()
    weighted_network.clear_edges()

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
