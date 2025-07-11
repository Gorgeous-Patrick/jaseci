import networkx as nx
import matplotlib.pyplot as plt

import networkx as nx
import matplotlib.pyplot as plt

def plot_and_save(G1: nx.Graph, G2: nx.Graph, filename1="G1.png", filename2="G2.png"):
    # Use a shared layout from the union of nodes
    all_nodes = set(G1.nodes()).union(G2.nodes())
    layout_graph = nx.Graph()
    layout_graph.add_nodes_from(all_nodes)
    pos = nx.kamada_kawai_layout(layout_graph)

    # --- Plot G1: Solid edges ---
    plt.figure(figsize=(8, 6))
    node_colors = [G1.nodes[n]["color"] for n in G1.nodes()]

    # This will place node IDs (or custom labels) on the nodes
    labels = {n: G1.nodes[n]["node_name"] for n in G1.nodes() if G1.nodes[n]["node_name"] is not None}  # You can customize this

    nx.draw_networkx_nodes(G1, pos, nodelist=G1.nodes(), node_size=500, node_color=node_colors)
    nx.draw_networkx_labels(G1, pos, labels)
    nx.draw_networkx_edges(G1, pos, edge_color='black', style='solid', width=1, arrows=G1.is_directed())
    plt.axis('off')
    plt.tight_layout()
    plt.savefig(filename1, dpi=300)
    plt.close()

    # --- Plot G2: Dashed edges with weight labels ---
    plt.figure(figsize=(8, 6))
    nx.draw_networkx_nodes(G2, pos, nodelist=G2.nodes(), node_size=500, node_color=node_colors, label=labels)
    nx.draw_networkx_edges(G2, pos, edge_color='blue', style='dashed', width=1, arrows=G2.is_directed())
    nx.draw_networkx_labels(G2, pos, labels)
    plt.axis('off')
    plt.tight_layout()
    plt.savefig(filename2, dpi=300)
    plt.close()
