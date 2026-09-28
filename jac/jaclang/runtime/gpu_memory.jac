import from array { array }

obj ArenaLayout {
    has capacity: int,
        offsets: list[int],
        nbytes: int;
}

obj GpuMemoryPlan {
    has node_count: int,
        walker_count: int,
        graph_layout: ArenaLayout,
        walker_layout: ArenaLayout;

    def allocated_bytes -> int {
        return self.graph_layout.nbytes + self.walker_layout.nbytes;
    }

    def payload_bytes -> int {
        return 16 * self.node_count + 28 * self.walker_count;
    }
}

def arena_layout(
    count: int, item_sizes: list[int], previous_capacity: int = 0
) -> ArenaLayout {
    if count < 0 or previous_capacity < 0 {
        raise ValueError("GPU capacities must be nonnegative");
    }
    capacity = previous_capacity;
    if count > capacity {
        capacity = 1 << (count - 1).bit_length();
    }
    offsets: list[int] = [];
    end = 0;
    for size in item_sizes {
        end = ((end + 255) // 256) * 256;
        offsets.append(end);
        end += capacity * size;
    }
    return ArenaLayout(capacity, offsets, ((end + 255) // 256) * 256);
}

def memory_plan(
    nodes: int, walkers: int, graph_capacity: int = 0, walker_capacity: int = 0
) -> GpuMemoryPlan {
    return GpuMemoryPlan(
        nodes,
        walkers,
        arena_layout(nodes, [8, 8], graph_capacity),
        arena_layout(walkers, [8, 8, 8, 4], walker_capacity)
    );
}

obj ChainBuffers {
    has values: array,
        links: array,
        heads: array,
        initial: array,
        results: array,
        status: array;

    def arrays -> list[array] {
        return [
            self.values,
            self.links,
            self.heads,
            self.initial,
            self.results,
            self.status
        ];
    }
}

def chain_buffers(
    values: list[float], links: list[int], heads: list[int], initial: list[float]
) -> ChainBuffers {
    n = len(values);
    m = len(heads);
    if len(links) != n or len(initial) != m {
        raise ValueError("GPU graph and walker array lengths do not match");
    }
    result = ChainBuffers(
        array('d', values),
        array('q', links),
        array('q', heads),
        array('d', initial),
        array('d', [0.0]) * m,
        array('I', [4294967295]) * m
    );
    if [a.itemsize for a in result.arrays()] != [8, 8, 8, 8, 8, 4] {
        raise RuntimeError("Host array sizes do not match the GPU ABI");
    }
    return result;
}
