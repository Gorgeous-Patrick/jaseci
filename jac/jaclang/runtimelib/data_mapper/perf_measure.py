"""Performance measurement toolkit of jacpim."""

from jaclang.runtimelib.archetype import WalkerAnchor
from jaclang.runtimelib.data_mapper.simple_simulator import get_total_number_cycles
from jaclang.runtimelib.data_mapper.size_calc import calculate_size
import jaclang.compiler.unitree as uni

import networkx as nx


DPU_BANDWIDTH = 2.4 * 1024 * 1024 * 1024  # 2.4 GB/s
DPU_CYCLES = 101221
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

def print_performance_info(network: nx.DiGraph, mapping: dict[int, int], walker: WalkerAnchor, walker_code: uni.Archetype, trace: list[int]) -> None:
    """Print the performance information of a walker."""
    num_jumps = get_num_dpu_jumps(mapping, [trace])
    trace_len = len(trace)
    walker_size = calculate_size(walker.archetype)

    ability_list = walker_code.get_all_sub_nodes(uni.Ability)
    abilities = {ability.get_all_sub_nodes(uni.EventSignature)[0].get_all_sub_nodes(uni.Name)[0].value: ability for ability in ability_list}
    
    
    exec_number_cycles = get_total_number_cycles(trace, network, abilities)
    transfer_time = get_transfer_time(num_jumps, walker_size)
    # compute_time = get_compute_time(trace_len)
    compute_time = exec_number_cycles / DPU_CLOCK_FREQUENCY
    total = transfer_time + compute_time
    print("===============")
    print(f"Total number of jumps: {trace_len - 1}")
    print(f"Number of cross DPU jumps: {num_jumps}")
    print(f"Walker size: {walker_size} bytes")
    print(f"Transfer time: {transfer_time} seconds")
    print(f"Compute time: {compute_time} seconds")
    print(f"Simple Compute Cycles: {exec_number_cycles}")
    print(f"Total time: {total} seconds")
    print(f"Compute time percentage: {compute_time / total * 100:.5f}%")
    print(f"Transfer time percentage: {transfer_time / total * 100:.5f}%")


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