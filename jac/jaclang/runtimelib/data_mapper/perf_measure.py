"""Performance measurement toolkit of jacpim."""

def get_num_dpu_jumps(mapping: dict[int, int], traces: list[list[int]]) -> int:
    """Get the number of cross DPU jumps. Given the traces."""
    edge_set: list[tuple[int, int]] = []
    for trace in traces:
        for i in range(len(trace) - 1):
            edge = (trace[i], trace[i + 1])
            edge_set.append(edge)
    return len([edge for edge in edge_set if mapping[edge[0]] != mapping[edge[1]]])

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