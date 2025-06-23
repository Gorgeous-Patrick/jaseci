import os
import networkx as nx
from tqdm import tqdm
from data_prep import download_and_cache, get_subgraph
from partitioner import metis_partition, random_partition, calculate_performance
import matplotlib.pyplot as plt


SNAP_URL = "https://snap.stanford.edu/data/wiki-topcats.txt.gz"
DATA_DIR = "snap_data"
RAW_FILE = os.path.join(DATA_DIR, "wiki-topcats.txt.gz")
EXTRACTED_FILE = os.path.join(DATA_DIR, "wiki-topcats.txt")
SUBGRAPH_FILE = os.path.join(DATA_DIR, "wiki-topcats-subgraph.txt")

import networkx as nx
import random

def simulate_walkers(graph: nx.Graph):
    walker_traces = dict()

    for node in graph.nodes():
        trace = [node]  # first visit self
        neighbors = list(graph.neighbors(node))
        trace.extend(neighbors)
        walker_traces[node] = trace

    return walker_traces


def main():
    download_and_cache(RAW_FILE, EXTRACTED_FILE, SNAP_URL, DATA_DIR)
    # full_graph = load_full_graph()
    # subgraph = extract_subgraph(full_graph, target_size=300)
    subgraph = get_subgraph(EXTRACTED_FILE, SUBGRAPH_FILE, target_size=100, limit=1000, small=True)
    # What is the average number of neighbors for each node in the subgraph?
    print(f"Average degree of subgraph: {sum(dict(subgraph.degree()).values()) / subgraph.number_of_nodes()}")
    avg = 0
    for _ in range(10):
        random_partitioned_label = random_partition(subgraph, num_partitions=5)
        avg += calculate_performance(simulate_walkers(subgraph), random_partitioned_label)
    avg /= 10
    print(f"Average edges crossing partition boundaries for random partitioning: {avg}")
    metis_partitioned_label, labeled = metis_partition(subgraph, num_partitions=5)
    print("Metis partitioning performance: ", calculate_performance(simulate_walkers(subgraph), metis_partitioned_label))

    plot_and_save(subgraph, metis_partitioned_label, filename="subgraph_partitioned.png")
    
if __name__ == "__main__":
    main()
