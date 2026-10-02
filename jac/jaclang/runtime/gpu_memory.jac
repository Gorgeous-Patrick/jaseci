import from array { array }

enum GpuScalarType: str { FLOAT64 = "float64", INT64 = "int64", BOOL = "bool64" }

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
        report_layout: ArenaLayout = ArenaLayout(0, [], 0),
        tagged_reports: bool = False;

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
            + (8 * (1 + self.report_capacity * (2 if self.tagged_reports else 1)) * self.walker_count if self.report_capacity else 0)
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
        capacity: int,
        tags: array | None = None;
}

def report_buffers(walkers: int, capacity: int, dtype: GpuScalarType, tagged: bool = False) -> ReportBuffers {
    check_report_capacity(capacity, walkers);
    code = 'q' if dtype != GpuScalarType.FLOAT64 else 'd';
    return ReportBuffers(
        array('Q', [0]) * walkers,
        array('Q' if tagged else code, [0]) * (walkers * capacity),
        capacity,
        array('Q', [0]) * (walkers * capacity) if tagged else None
    );
}

def with_report_plan(plan: GpuMemoryPlan, reports: ReportBuffers | None, previous_capacity: int = 0) -> GpuMemoryPlan {
    if reports is not None {
        check_report_capacity(reports.capacity, plan.walker_count);
        plan.report_capacity = reports.capacity;
        plan.tagged_reports = reports.tags is not None;
        sizes = [8, 8 * reports.capacity];
        if plan.tagged_reports { sizes.append(8 * reports.capacity); }
        plan.report_layout = arena_layout(plan.walker_count, sizes, previous_capacity);
    }
    return plan;
}

def typed_columns(groups: Sequence[Sequence[float | int]], types: list[GpuScalarType], dtype: GpuScalarType) -> list[array] {
    if types and len(types) != len(groups) {
        raise ValueError("GPU column types do not match the field counts");
    }
    declared = types or [dtype for group in groups];
    return [array('d' if typ == GpuScalarType.FLOAT64 else 'q', group)
        for (typ, group) in zip(declared, groups)];
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
    extra_initial: Sequence[Sequence[float | int]] = (),
    node_dtypes: list[GpuScalarType] = [],
    state_dtypes: list[GpuScalarType] = []
) -> ChainBuffers {
    n = len(values);
    m = len(heads);
    if len(links) != n
        or len(initial) != m
        or any(len(v) != n for v in extra_values)
        or any(len(v) != m for v in extra_initial) {
        raise ValueError("GPU graph and walker array lengths do not match");
    }
    values_typed = typed_columns([values, *extra_values], node_dtypes, dtype);
    initials_typed = typed_columns([initial, *extra_initial], state_dtypes, dtype);
    outputs_typed = [array(v.typecode, [0]) * len(heads) for v in initials_typed];
    result = ChainBuffers(
        values_typed[0],
        array('q', links),
        array('q', heads),
        initials_typed[0],
        outputs_typed[0],
        array('I', [4294967295]) * m,
        values_typed[1:],
        initials_typed[1:],
        outputs_typed[1:]
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
    extra_initial: Sequence[Sequence[float | int]] = (),
    node_dtypes: list[GpuScalarType] = [],
    state_dtypes: list[GpuScalarType] = []
) -> CsrBuffers {
    check_csr_limits(queue_capacity, max_visits);
    if len(offsets) != len(values) + 1
        or len(initial) != len(heads)
        or any(len(v) != len(values) for v in extra_values)
        or any(len(v) != len(heads) for v in extra_initial) {
        raise ValueError("CSR graph and walker array lengths do not match");
    }
    values_typed = typed_columns([values, *extra_values], node_dtypes, dtype);
    initials_typed = typed_columns([initial, *extra_initial], state_dtypes, dtype);
    outputs_typed = [array(v.typecode, [0]) * len(heads) for v in initials_typed];
    result = CsrBuffers(
        values_typed[0],
        array('q', offsets),
        array('q', targets),
        array('q', heads),
        initials_typed[0],
        outputs_typed[0],
        array('I', [4294967295]) * len(heads),
        queue_capacity,
        max_visits,
        values_typed[1:],
        initials_typed[1:],
        outputs_typed[1:]
    );
    if [a.itemsize for a in result.arrays()]
        != [8] * (6 + len(extra_values) + 2 * len(extra_initial)) + [4] {
        raise RuntimeError("Host array sizes do not match the CSR GPU ABI");
    }
    return result;
}
