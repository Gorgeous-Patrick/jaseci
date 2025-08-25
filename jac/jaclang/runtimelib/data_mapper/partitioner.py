"""Graph Partitioning binding."""

import random
from collections import defaultdict

# import metis

import networkx as nx

DPU_SIZE_LIMIT = 64 * 1024 * 1024
DPU_NUM = 2560

def fennel_partition(
    graph: nx.DiGraph, num_partitions: int, capacity: int
):  # noqa: ANN201
    """Fennel Partitioner."""
    n = graph.number_of_nodes()
    beta = 1.5
    alpha = n / (num_partitions**beta)
    lambd = 1.0

    partitions = defaultdict(set)
    partition_sizes = [0] * num_partitions
    assignment: dict[str, int] = {}

    nodes = list(graph.nodes())
    random.shuffle(nodes)  # Random streaming order

    for node in nodes:
        neighbor_counts = [0] * num_partitions
        for neighbor in graph.neighbors(node):
            if neighbor in assignment:
                p = assignment[neighbor]
                neighbor_counts[p] += 1

        # Compute FENNEL score for each partition
        scores = []
        for p in range(num_partitions):
            if partition_sizes[p] >= capacity:
                scores.append(float("inf"))  # prevent overflow
            else:
                score = -lambd * neighbor_counts[p] + alpha * (
                    partition_sizes[p] ** beta
                )
                scores.append(score)

        # Select partition with minimal score
        best_partition = scores.index(min(scores))
        assignment[node] = best_partition
        partitions[best_partition].add(node)
        partition_sizes[best_partition] += 1

    return assignment, partitions


# def metis_partition(graph: nx.DiGraph, num_partitions: int):  # noqa: ANN201
#     """Metis partitioner."""
#     (edgecuts, parts) = metis.part_graph(
#         metis.networkx_to_metis(graph),
#         nparts=num_partitions,
#         # recursive=True,
#         # tpwgts=[1 / num_partitions] * num_partitions,
#         # ufactor=30,
#     )
#     res = {}
#     for i, name in enumerate(graph.nodes()):
#         res[name] = parts[i]
#     return res

def round_robin_partition(paths: list[list[int]], network: nx.DiGraph):  # noqa: ANN201
    # MAX_PARTITION_SIZE =   # Arbitrary limit to prevent overflow
    # TODO: Change this size to a more accurate one.
    RESERVED_SIZE = 1024
    MAX_PARTITION_SIZE = DPU_SIZE_LIMIT - RESERVED_SIZE
    dpu_data: list[set[int]] = [set() for _ in range(DPU_NUM)]
    for idx, path in enumerate(paths):
        dpu = idx % DPU_NUM
        for node in path:
            node_size = network.nodes[node].get("node_size")
            while len(dpu_data[dpu]) >= MAX_PARTITION_SIZE - node_size:
                dpu = (dpu + 1) % DPU_NUM
            dpu_data[dpu].add(node)
    # return a dict mapping node to partition
    res = {}
    for dpu, nodes in enumerate(dpu_data):
        for node in nodes:
            res[node] = dpu
    return res, dpu_data

def random_partition(graph: nx.DiGraph, num_partitions: int):  # noqa: ANN201
    """Random partitioner (baseline)."""
    graph = graph.copy()
    res = {}
    for _, name in enumerate(graph.nodes()):
        res[name] = random.randint(0, num_partitions - 1)
    return res


def calculate_performance(walker_traces: dict, label: dict[str, int]):  # noqa: ANN201
    """Calculate the performance."""
    res = 0
    for _node, trace in walker_traces.items():
        edges = list(zip(trace[:-1], trace[1:]))
        for u, v in edges:
            if label[u] != label[v]:
                # print(f"Edge ({u}, {v}) crosses partition boundaries: {label[u]} vs {label[v]}")
                res += 1
    print(f"Total edges crossing partition boundaries: {res}")
    return res
