"""Graph Partitioning binding."""

import random
from collections import defaultdict
import networkx as nx

DPU_SIZE_LIMIT = 1024
DPU_NUM = 50
RESERVED_SIZE = 128
MAX_PARTITION_SIZE = DPU_SIZE_LIMIT - RESERVED_SIZE

class NodeDistribution:
    def __init__(self):
        self.node_to_partition = {}
        self.partition_availability = [0] * DPU_NUM
    def add_node(self, node: int, partition: int, node_size: int):
        self.node_to_partition[node] = partition
        self.partition_availability[partition] += node_size
        assert self.partition_availability[partition] <= MAX_PARTITION_SIZE

    def node_assigned(self, node: int):
        return node in self.node_to_partition.keys()
    
    def available_partitions(self, node_size: int):
        return [
            i for i in range(DPU_NUM)
            if self.partition_availability[i] + node_size <= MAX_PARTITION_SIZE
        ]
    
    def get_dpu_data_amount(self):
        return self.partition_availability

    def get_partition(self):
        return self.node_to_partition

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

def round_robin_partition(paths: list[list[int]], network: nx.DiGraph):  # noqa: ANN201
    node_distribution = NodeDistribution()
    for path in paths:
        for node in path:
            # If node has been assigned, then skip it.
            if node_distribution.node_assigned(node):
                continue
            node_size = network.nodes[node].get("node_size", 0)
            available_partitions = node_distribution.available_partitions(node_size)
            if not available_partitions:
                print("No available partition found")
                continue
            node_distribution.add_node(node, available_partitions[0], node_size)
    for node in network.nodes():
        if not node_distribution.node_assigned(node):
            node_size = network.nodes[node].get("node_size", 0)
            available_partitions = node_distribution.available_partitions(node_size)
            if not available_partitions:
                continue
            node_distribution.add_node(node, available_partitions[0], node_size)
    res = node_distribution.get_partition()
    assert(all(node in res.keys() for node in network.nodes()))
    return res

def random_partition(paths: list[list[int]], network: nx.DiGraph):  # noqa: ANN201
    """Random partitioner (baseline)."""
    res = {}
    node_distribution = NodeDistribution()
    for _, name in enumerate(network.nodes()):
        # res[name] = random.randint(0, DPU_NUM - 1)
        dpu = random.choice(node_distribution.available_partitions(network.nodes[name].get("node_size")))
        assert dpu is not None
        node_distribution.add_node(name, dpu, network.nodes[name].get("node_size"))
    res = node_distribution.get_partition()
    assert(all(node in res.keys() for node in network.nodes()))
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
    return res
