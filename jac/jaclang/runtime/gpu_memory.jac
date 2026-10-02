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
        queue_layout: ArenaLayout = ArenaLayout(0, [], 0),
        node_field_count: int = 1,
        state_field_count: int = 1,
        report_capacity: int = 0,
        report_layout: ArenaLayout = ArenaLayout(0, [], 0);

    def allocated_bytes -> int {
        return self.graph_layout.nbytes
            + self.walker_layout.nbytes
            + self.edge_layout.nbytes
            + self.queue_layout.nbytes
            + self.report_layout.nbytes;
    }

    def payload_bytes -> int {
        return 8 * (self.node_field_count + 1) * self.node_count
            + (12 + 16 * self.state_field_count) * self.walker_count
            + (8 * (1 + self.report_capacity) * self.walker_count if self.report_capacity else 0)
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
    nodes: int,
    walkers: int,
    graph_capacity: int = 0,
    walker_capacity: int = 0,
    node_field_count: int = 1,
    state_field_count: int = 1
) -> GpuMemoryPlan {
    if type(node_field_count) is not int or node_field_count < 1 {
        raise ValueError("GPU node field count must be a positive integer");
    }
    if type(state_field_count) is not int or state_field_count < 1 {
        raise ValueError("GPU state field count must be a positive integer");
    }
    return GpuMemoryPlan(
        nodes,
        walkers,
        arena_layout(nodes, [8] * (node_field_count + 1), graph_capacity),
        arena_layout(walkers, [8] * (1 + 2 * state_field_count) + [4], walker_capacity),
        node_field_count=node_field_count,
        state_field_count=state_field_count
    );
}

def check_report_capacity(capacity: int, walkers: int = 0) {
    if type(capacity) is not int or not 0 < capacity <= (2 ** 63 - 1) // 8 {
        raise ValueError("GPU report_capacity must be a positive addressable integer");
    }
    if walkers < 0 or walkers * (capacity + 1) > (2 ** 63 - 1) // 8 {
        raise ValueError("GPU report storage exceeds the addressable byte range");
    }
}

obj ReportBuffers {
    has counts: array,
        values: array,
        capacity: int;
}

def report_buffers(walkers: int, capacity: int, dtype: GpuScalarType) -> ReportBuffers {
    check_report_capacity(capacity, walkers);
    code = 'q' if dtype == GpuScalarType.INT64 else 'd';
    return ReportBuffers(array('Q', [0]) * walkers, array(code, [0]) * (walkers * capacity), capacity);
}

def with_report_plan(plan: GpuMemoryPlan, reports: ReportBuffers | None, previous_capacity: int = 0) -> GpuMemoryPlan {
    if reports is not None {
        check_report_capacity(reports.capacity, plan.walker_count);
        plan.report_capacity = reports.capacity;
        plan.report_layout = arena_layout(plan.walker_count, [8, 8 * reports.capacity], previous_capacity);
    }
    return plan;
}

obj ChainBuffers {
    has values: array,
        links: array,
        heads: array,
        initial: array,
        results: array,
        status: array,
        extra_values: list[array] = [],
        extra_initial: list[array] = [],
        extra_results: list[array] = [],
        reports: ReportBuffers | None = None;

    def columns -> list[array] {
        return [self.values, *self.extra_values];
    }

    def initial_columns -> list[array] {
        return [self.initial, *self.extra_initial];
    }

    def result_columns -> list[array] {
        return [self.results, *self.extra_results];
    }

    def arrays -> list[array] {
        return [
            *self.columns(),
            self.links,
            self.heads,
            *self.initial_columns(),
            *self.result_columns(),
            self.status
        ];
    }
}

def chain_buffers(
    values: Sequence[float | int],
    links: list[int],
    heads: list[int],
    initial: Sequence[float | int],
    dtype: GpuScalarType = GpuScalarType.FLOAT64,
    extra_values: Sequence[Sequence[float | int]] = (),
    extra_initial: Sequence[Sequence[float | int]] = ()
) -> ChainBuffers {
    n = len(values);
    m = len(heads);
    if len(links) != n
        or len(initial) != m
        or any(len(v) != n for v in extra_values)
        or any(len(v) != m for v in extra_initial) {
        raise ValueError("GPU graph and walker array lengths do not match");
    }
    code = 'q' if dtype == GpuScalarType.INT64 else 'd';
    result = ChainBuffers(
        array(code, values),
        array('q', links),
        array('q', heads),
        array(code, initial),
        array(code, [0]) * m,
        array('I', [4294967295]) * m,
        [array(code, v) for v in extra_values],
        [array(code, v) for v in extra_initial],
        [array(code, [0]) * m for v in extra_initial]
    );
    if [a.itemsize for a in result.arrays()]
        != [8] * (5 + len(extra_values) + 2 * len(extra_initial)) + [4] {
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
    queue_slots: int = 0,
    node_field_count: int = 1,
    state_field_count: int = 1
) -> GpuMemoryPlan {
    check_csr_limits(queue_capacity, 1);
    if walkers < 0 or walkers * queue_capacity > (2 ** 63 - 1) // 8 {
        raise ValueError("CSR queue storage exceeds the addressable byte range");
    }
    if type(node_field_count) is not int or node_field_count < 1 {
        raise ValueError("GPU node field count must be a positive integer");
    }
    if type(state_field_count) is not int or state_field_count < 1 {
        raise ValueError("GPU state field count must be a positive integer");
    }
    graph_layout = arena_layout(nodes, [8] * (node_field_count + 1), graph_capacity);

    if nodes or walkers or graph_capacity {
        graph_layout.nbytes = (
            (graph_layout.offsets[-1] + (graph_layout.capacity + 1) * 8 + 255) // 256
        )
            * 256;
    }
    return GpuMemoryPlan(
        nodes,
        walkers,
        graph_layout,
        arena_layout(walkers, [8] * (1 + 2 * state_field_count) + [4], walker_capacity),
        'csr',
        edges,
        queue_capacity,
        arena_layout(edges, [8], edge_capacity),
        arena_layout(walkers * queue_capacity, [8], queue_slots),
        node_field_count,
        state_field_count
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
        max_visits: int,
        extra_values: list[array] = [],
        extra_initial: list[array] = [],
        extra_results: list[array] = [],
        reports: ReportBuffers | None = None;

    def columns -> list[array] {
        return [self.values, *self.extra_values];
    }

    def initial_columns -> list[array] {
        return [self.initial, *self.extra_initial];
    }

    def result_columns -> list[array] {
        return [self.results, *self.extra_results];
    }

    def arrays -> list[array] {
        return [
            *self.columns(),
            self.offsets,
            self.targets,
            self.heads,
            *self.initial_columns(),
            *self.result_columns(),
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
    max_visits: int = 1000000,
    extra_values: Sequence[Sequence[float | int]] = (),
    extra_initial: Sequence[Sequence[float | int]] = ()
) -> CsrBuffers {
    check_csr_limits(queue_capacity, max_visits);
    if len(offsets) != len(values) + 1
        or len(initial) != len(heads)
        or any(len(v) != len(values) for v in extra_values)
        or any(len(v) != len(heads) for v in extra_initial) {
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
        max_visits,
        [array(code, v) for v in extra_values],
        [array(code, v) for v in extra_initial],
        [array(code, [0]) * len(heads) for v in extra_initial]
    );
    if [a.itemsize for a in result.arrays()]
        != [8] * (6 + len(extra_values) + 2 * len(extra_initial)) + [4] {
        raise RuntimeError("Host array sizes do not match the CSR GPU ABI");
    }
    return result;
}
