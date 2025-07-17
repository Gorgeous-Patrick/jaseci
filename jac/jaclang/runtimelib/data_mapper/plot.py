"""Plotting diagrams."""

import matplotlib.pyplot as plt

import networkx as nx


def plot_and_save(
    g1: nx.Graph,
    g2: nx.Graph,
    filename1: str = "g1.png",
    filename2: str = "g2.png",
) -> None:
    """Plot graphs and save."""
    node_colors = [g1.nodes[n]["color"] for n in g1.nodes()]
    node_id = {n: g1.nodes[n]["node_id"] or "" for n in g1.nodes()}
    # Use a shared layout from the union of nodes
    all_nodes = set(g1.nodes()).union(g2.nodes())
    layout_graph = nx.Graph()
    layout_graph.add_nodes_from(all_nodes)
    pos = nx.kamada_kawai_layout(layout_graph)

    # --- Plot g1: Solid edges ---
    plt.figure(figsize=(8, 6))
    nx.draw_networkx_nodes(
        g1, pos, nodelist=g1.nodes(), node_size=100, node_color=node_colors
    )
    nx.draw_networkx_labels(g1, pos, node_id)
    nx.draw_networkx_edges(
        g1, pos, edge_color="black", style="solid", width=1, arrows=g1.is_directed()
    )
    labels1 = nx.get_edge_attributes(g1, "weight")
    if labels1:
        nx.draw_networkx_edge_labels(
            g1, pos, edge_labels=labels1, font_size=10, font_color="black"
        )
    plt.axis("off")
    plt.tight_layout()
    plt.savefig(filename1, dpi=300)
    plt.close()

    # --- Plot g2: Dashed edges with weight labels ---
    plt.figure(figsize=(8, 6))
    nx.draw_networkx_nodes(
        g2, pos, nodelist=g2.nodes(), node_size=100, node_color=node_colors
    )
    nx.draw_networkx_labels(g2, pos, node_id)
    nx.draw_networkx_edges(
        g2, pos, edge_color="blue", style="dashed", width=1, arrows=g2.is_directed()
    )
    # labels2 = nx.get_edge_attributes(g2, 'weight')
    # if labels2:
    #     nx.draw_networkx_edge_labels(g2, pos, edge_labels=labels2, font_size=10, font_color='blue')
    plt.axis("off")
    plt.tight_layout()
    plt.savefig(filename2, dpi=300)
    plt.close()
