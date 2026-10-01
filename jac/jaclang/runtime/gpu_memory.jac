import from array { array }

enum GpuScalarType: str { FLOAT64 = "float64", INT64 = "int64" }

obj ArenaLayout {
    has capacity: int,
        offsets: list[int],
        nbytes: int;
}

obj GpuMemoryPlan {
    has node_count: int,
        walker_count: int,
        graph_layout: ArenaLayout,
        walker_layout: ArenaLayout,
        graph_format: str = 'chain',
        edge_count: int = 0,
        queue_capacity: int = 0,
        edge_layout: ArenaLayout = ArenaLayout(0, [], 0),
        queue_layout: ArenaLayout = ArenaLayout(0, [], 0);

    def allocated_bytes -> int {
        return self.graph_layout.nbytes
            + self.walker_layout.nbytes
            + self.edge_layout.nbytes
            + self.queue_layout.nbytes;
    }

    def payload_bytes -> int {
        return 16 * self.node_count
            + 28 * self.walker_count
            + (
                8 + 8 * self.edge_count + 8 * self.walker_count * self.queue_capacity
                    if self.graph_format == 'csr'
                    else 0
            );
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
    values: Sequence[float | int],
    links: list[int],
    heads: list[int],
    initial: Sequence[float | int],
    dtype: GpuScalarType = GpuScalarType.FLOAT64
) -> ChainBuffers {
    n = len(values);
    m = len(heads);
    if len(links) != n or len(initial) != m {
        raise ValueError("GPU graph and walker array lengths do not match");
    }
    code = 'q' if dtype == GpuScalarType.INT64 else 'd';
    result = ChainBuffers(
        array(code, values),
        array('q', links),
        array('q', heads),
        array(code, initial),
        array(code, [0]) * m,
        array('I', [4294967295]) * m
    );
    if [a.itemsize for a in result.arrays()] != [8, 8, 8, 8, 8, 4] {
        raise RuntimeError("Host array sizes do not match the GPU ABI");
    }
    return result;
}

def check_csr_limits(queue_capacity: int, max_visits: int) {
    for value in (queue_capacity, max_visits) {
        if type(value) is not int or not 0 < value < 2 ** 63 {
            raise ValueError(
                "CSR queue_capacity and max_visits must be positive int64 values"
            );
        }
    }
    if queue_capacity > (2 ** 63 - 1) // 8 {
        raise ValueError("CSR queue capacity exceeds the addressable byte range");
    }
}

def csr_memory_plan(
    nodes: int,
    edges: int,
    walkers: int,
    queue_capacity: int,
    graph_capacity: int = 0,
    edge_capacity: int = 0,
    walker_capacity: int = 0,
    queue_slots: int = 0
) -> GpuMemoryPlan {
    check_csr_limits(queue_capacity, 1);
    if walkers < 0 or walkers * queue_capacity > (2 ** 63 - 1) // 8 {
        raise ValueError("CSR queue storage exceeds the addressable byte range");
    }
    graph_layout = arena_layout(nodes, [8, 8], graph_capacity);

    if nodes or walkers or graph_capacity {
        graph_layout.nbytes = (
            (graph_layout.offsets[1] + (graph_layout.capacity + 1) * 8 + 255) // 256
        )
            * 256;
    }
    return GpuMemoryPlan(
        nodes,
        walkers,
        graph_layout,
        arena_layout(walkers, [8, 8, 8, 4], walker_capacity),
        'csr',
        edges,
        queue_capacity,
        arena_layout(edges, [8], edge_capacity),
        arena_layout(walkers * queue_capacity, [8], queue_slots)
    );
}

obj CsrBuffers {
    has values: array,
        offsets: array,
        targets: array,
        heads: array,
        initial: array,
        results: array,
        status: array,
        queue_capacity: int,
        max_visits: int;

    def arrays -> list[array] {
        return [
            self.values,
            self.offsets,
            self.targets,
            self.heads,
            self.initial,
            self.results,
            self.status
        ];
    }
}

def csr_buffers(
    values: Sequence[float | int],
    offsets: list[int],
    targets: list[int],
    heads: list[int],
    initial: Sequence[float | int],
    dtype: GpuScalarType = GpuScalarType.FLOAT64,
    queue_capacity: int = 1024,
    max_visits: int = 1000000
) -> CsrBuffers {
    check_csr_limits(queue_capacity, max_visits);
    if len(offsets) != len(values) + 1 or len(initial) != len(heads) {
        raise ValueError("CSR graph and walker array lengths do not match");
    }
    code = 'q' if dtype == GpuScalarType.INT64 else 'd';
    result = CsrBuffers(
        array(code, values),
        array('q', offsets),
        array('q', targets),
        array('q', heads),
        array(code, initial),
        array(code, [0]) * len(heads),
        array('I', [4294967295]) * len(heads),
        queue_capacity,
        max_visits
    );
    if [a.itemsize for a in result.arrays()] != [8, 8, 8, 8, 8, 8, 4] {
        raise RuntimeError("Host array sizes do not match the CSR GPU ABI");
    }
    return result;
}
