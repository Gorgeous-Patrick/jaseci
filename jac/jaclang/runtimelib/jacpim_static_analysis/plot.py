"""Plotting diagrams."""

import matplotlib.pyplot as plt

import networkx as nx

from .info_extract import get_node_info_from_node_arch


def plot_one_graph(graph: nx.MultiDiGraph, pos: dict, filename: str) -> None:
    """Plot and save one graph."""
    plt.figure()
    nx.draw_networkx_nodes(graph, pos, node_size=100)
    display_names = {
        n: get_node_info_from_node_arch(graph.nodes[n]["archetype"]).display_name
        for n in graph.nodes()
    }
    nx.draw_networkx_labels(graph, pos, display_names, font_size=10)
    nx.draw_networkx_edges(graph, pos)
    plt.savefig(filename, dpi=300)
    plt.close()
