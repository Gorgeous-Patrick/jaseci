import os
import urllib.request
import gzip
import shutil
import networkx as nx
from tqdm import tqdm
import random
import matplotlib.pyplot as plt

def download_and_cache(raw_file: str, extracted_file: str, url: str, data_dir:str ="snap_data"):
    os.makedirs(data_dir, exist_ok=True)
    if not os.path.exists(raw_file):
        print("Downloading SNAP dataset...")
        urllib.request.urlretrieve(url, raw_file)
    else:
        print("Dataset already downloaded.")

    if not os.path.exists(extracted_file):
        print("Extracting...")
        with gzip.open(raw_file, 'rb') as f_in:
            with open(extracted_file, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)
    else:
        print("Dataset already extracted.")


def load_full_graph(extracted_file: str, limit: int | None= None):
    print("Loading full graph...")
    G = nx.DiGraph()
    with open(extracted_file, 'r') as f:
        for line in f:
            if limit is not None and G.number_of_edges() >= limit:
                break
            u, v = map(int, line.strip().split())
            G.add_edge(u, v)
            # print(G.number_of_edges() / limit)
    print(f"Full graph loaded: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges")
    return G

def extract_subgraph_small(G, subgraph_file, target_size=1000):
    print(f"Extracting subgraph with ~{target_size} nodes...")
    nodes = list(G.nodes())
    random.seed(42)
    seed_node = random.choice(nodes)
    sub_nodes = set()

    # BFS expansion until target size
    queue = [seed_node]
    while queue and len(sub_nodes) < target_size:
        node = queue.pop(0)
        if node in sub_nodes:
            continue
        sub_nodes.add(node)
        neighbors = list(G.successors(node)) + list(G.predecessors(node))
        random.shuffle(neighbors)
        queue.extend(neighbors)

    subgraph = G.subgraph(sub_nodes).copy()
    # Rename the nodes to be contiguous integers
    mapping = {old: new for new, old in enumerate(subgraph.nodes())}
    subgraph = nx.relabel_nodes(subgraph, mapping)
    print(f"Subgraph: {subgraph.number_of_nodes()} nodes, {subgraph.number_of_edges()} edges")

    # Optionally save for inspection
    nx.write_edgelist(subgraph, subgraph_file, data=False)
    print(f"Subgraph written to {subgraph_file}")
    return subgraph




def extract_subgraph(G, subgraph_file, target_size=1000):
    print(f"Extracting subgraph with ~{target_size} nodes...")
    nodes = list(G.nodes())
    random.seed(42)
    seed_node = random.choice(nodes)
    sub_nodes = set()

    # BFS expansion until target size
    queue = [seed_node]
    while queue and len(sub_nodes) < target_size:
        node = queue.pop(0)
        if node in sub_nodes:
            continue
        sub_nodes.add(node)
        neighbors = list(G.successors(node)) + list(G.predecessors(node))
        random.shuffle(neighbors)
        queue.extend(neighbors)

    subgraph = G.subgraph(sub_nodes).copy()
    # Rename the nodes to be contiguous integers
    mapping = {old: new for new, old in enumerate(subgraph.nodes())}
    subgraph = nx.relabel_nodes(subgraph, mapping)
    print(f"Subgraph: {subgraph.number_of_nodes()} nodes, {subgraph.number_of_edges()} edges")

    # Optionally save for inspection
    nx.write_edgelist(subgraph, subgraph_file, data=False)
    print(f"Subgraph written to {subgraph_file}")
    return subgraph

import random



def get_subgraph(extracted_file, subgraph_file, target_size=1000, limit=1000000, small=False):
    if os.path.exists(subgraph_file):
        print(f"Subgraph already exists at {subgraph_file}. Loading...")
        return nx.read_edgelist(subgraph_file, create_using=nx.DiGraph(), data=False)
    else:
        G = load_full_graph(extracted_file, limit=limit)
        if small:
            return extract_subgraph_small(G, subgraph_file, target_size)
        else:
            return extract_subgraph(G, subgraph_file, target_size)

def plot_and_save(subgraph, label, filename="subgraph.png"):
    colors = ['red','blue','green', 'yellow', 'orange']
    for i, name in enumerate(subgraph.nodes()):
        subgraph.nodes[name]['color'] = label[name] % len(colors)
    
    # Save the dot file for visualization
    # write_dot(subgraph, "subgraph.dot")
    # Visualize the subgraph with edge weights
    pos=nx.kamada_kawai_layout(subgraph) # pos = nx.nx_agraph.graphviz_layout(G)
    nx.draw_networkx(subgraph,pos, node_color=[subgraph.nodes[n]['color'] for n in subgraph.nodes()], with_labels=False, node_size=10, arrows=True)
    labels = nx.get_edge_attributes(subgraph,'weight')
    nx.draw_networkx_edge_labels(subgraph,pos,edge_labels=labels, font_size=3)
    # nx.draw_kamada_kawai(subgraph, node_color=[subgraph.nodes[n]['color'] for n in subgraph.nodes()], with_labels=False)
    plt.savefig(filename, dpi=300)
