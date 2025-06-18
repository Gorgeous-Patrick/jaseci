"""Performance measurement toolkit of jacpim."""


def get_num_dpu_jumps(mapping: dict[int, int], traces: list[list[int]]) -> int:
    """Get the number of cross DPU jumps. Given the traces."""
    edge_set: list[tuple[int, int]] = []
    for trace in traces:
        for i in range(len(trace) - 1):
            edge = (trace[i], trace[i + 1])
            edge_set.append(edge)
    return len([edge for edge in edge_set if mapping[edge[0]] != mapping[edge[1]]])
