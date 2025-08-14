"""Performance measurement toolkit of jacpim."""

from jaclang.runtimelib.archetype import WalkerAnchor
from jaclang.runtimelib.data_mapper.size_calc import calculate_size

import networkx as nx


DPU_BANDWIDTH = 2.4 * 1024 * 1024 * 1024  # 2.4 GB/s
DPU_CYCLES = 3400
DPU_CLOCK_FREQUENCY = 450 * 2**20

def get_num_dpu_jumps(mapping: dict[int, int], traces: list[list[int]]) -> int:
    """Get the number of cross DPU jumps. Given the traces."""
    edge_set: list[tuple[int, int]] = []
    for trace in traces:
        for i in range(len(trace) - 1):
            edge = (trace[i], trace[i + 1])
            edge_set.append(edge)
    return len([edge for edge in edge_set if mapping[edge[0]] != mapping[edge[1]]])

def get_transfer_time(num_jumps: int, walker_size: int) -> float:
    """Get the transfer time of a walker with a given number of jumps.""" 
    data_transfer_time = num_jumps * walker_size / DPU_BANDWIDTH * 2
    return data_transfer_time

def get_compute_time(trace_len: int) -> float:
    """Get the compute time of a walker with a given number of jumps."""
    compute_time = trace_len * DPU_CYCLES / DPU_CLOCK_FREQUENCY
    return compute_time

def print_performance_info(mapping: dict[int, int], walker: WalkerAnchor, trace: list[int]) -> None:
    """Print the performance information of a walker."""
    num_jumps = get_num_dpu_jumps(mapping, [trace])
    trace_len = len(trace)
    walker_size = calculate_size(walker.archetype)
    transfer_time = get_transfer_time(num_jumps, walker_size)
    compute_time = get_compute_time(trace_len)
    total = transfer_time + compute_time
    print(f"Number of jumps: {num_jumps}")
    print(f"Walker size: {walker_size} bytes")
    print(f"Transfer time: {transfer_time} seconds")
    print(f"Compute time: {compute_time} seconds")
    print(f"Total time: {total} seconds")
    print(f"Compute time percentage: {compute_time / total * 100:.2f}%")
    print(f"Transfer time percentage: {transfer_time / total * 100:.2f}%")


def get_num_dpu_jumps_adaptive(mapping: dict[int, int], set_traces: list[list[set[int]]]) -> int:
    """Get the number of cross DPU jumps. Given the traces."""
    paths: list[list[int]] = []
    for set_trace in set_traces:
        path: list[int] = []
        dpu = -1
        for i in range(len(set_trace)):
            elements = set_trace[i]
            while len(elements) > 0:
                dpu = mapping[next(iter(elements))]
                in_dpu_elements = set(s for s in set_trace[i] if mapping[s] == dpu)
                path.extend(in_dpu_elements)
                elements = elements - in_dpu_elements
        paths.append(path)
    edge_set: list[tuple[int, int]] = []
    for path in paths:
        for i in range(len(path) - 1):
            edge = (path[i], path[i + 1])
            edge_set.append(edge)
    return len([edge for edge in edge_set if mapping[edge[0]] != mapping[edge[1]]])