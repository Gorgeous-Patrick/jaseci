"""Plotting diagrams."""

import matplotlib.pyplot as plt

import networkx as nx


def _plot_one_diagram(graph: nx.DiGraph, edge_color: str, edge_style: str) -> None:
    plt.figure()
    # Use a shared layout from the union of nodes
    layout_graph = nx.Graph()
    all_nodes = set(graph.nodes())
    layout_graph.add_nodes_from(all_nodes)
    pos = nx.kamada_kawai_layout(layout_graph)
    node_id = {n: graph.nodes[n]["node_id"] or "" for n in graph.nodes()}
    # Separate nodes by is_starting_node attribute
    starting_nodes = [
        n for n in graph.nodes() if graph.nodes[n].get("is_starting_node", False)
    ]
    other_nodes = [
        n for n in graph.nodes() if not graph.nodes[n].get("is_starting_node", False)
    ]
    # Get colors for each group
    starting_colors = [graph.nodes[n]["color"] for n in starting_nodes]
    other_colors = [graph.nodes[n]["color"] for n in other_nodes]
    # Draw starting nodes as squares
    if starting_nodes:
        nx.draw_networkx_nodes(
            graph,
            pos,
            nodelist=starting_nodes,
            node_size=100,
            node_color=starting_colors,
            node_shape="^",
        )
    # Draw other nodes as circles
    if other_nodes:
        nx.draw_networkx_nodes(
            graph,
            pos,
            nodelist=other_nodes,
            node_size=100,
            node_color=other_colors,
            node_shape="o",
        )
    nx.draw_networkx_labels(graph, pos, node_id)
    nx.draw_networkx_edges(
        graph,
        pos,
        edge_color=edge_color,
        style=edge_style,
        width=1,
        arrows=graph.is_directed(),
    )
    labels1 = nx.get_edge_attributes(graph, "weight")
    if labels1:
        nx.draw_networkx_edge_labels(
            graph, pos, edge_labels=labels1, font_size=10, font_color="black"
        )
    plt.axis("off")
    plt.tight_layout()


def plot_and_save(
    input_data_graph: nx.DiGraph,
    access_pattern_graph: nx.DiGraph,
    walker_trace_graph: nx.DiGraph,
    filename1: str = "input_data_graph.png",
    filename2: str = "access_pattern_graph.png",
    filename3: str = "walker_trace.png",
) -> None:
    """Plot graphs and save."""
    # --- Plot input_data_graph: Solid edges ---
    _plot_one_diagram(input_data_graph, "black", "solid")
    plt.savefig(filename1, dpi=300)
    plt.close()

    # --- Plot access_pattern_graph: Dashed edges with weight labels ---
    _plot_one_diagram(access_pattern_graph, "blue", "dashed")
    plt.savefig(filename2, dpi=300)
    plt.close()

    # --- Plot access_pattern_graph: Dashed edges with weight labels ---
    _plot_one_diagram(walker_trace_graph, "green", "dashed")
    plt.savefig(filename3, dpi=300)
    plt.close()
