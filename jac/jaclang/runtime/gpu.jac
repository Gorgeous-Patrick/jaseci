import hashlib;
import struct;
import sys;
import from pathlib { Path }
import from threading { get_ident }
import from typing { cast }
import from jaclang.runtime.archetype {
    WalkerArchetype,
    NodeArchetype,
    EdgeArchetype,
    NodeAnchor,
    anchor_key
}
import from jaclang.runtime.gpu_memory {
    ChainBuffers,
    CsrBuffers,
    GpuScalarType,
    GpuMemoryPlan,
    chain_buffers,
    csr_buffers,
    csr_memory_plan,
    check_csr_limits,
    check_report_capacity,
    report_buffers,
    with_report_plan,
    memory_plan as make_memory_plan
}
import from jaclang.runtime.gpu_cuda { CudaSession }

obj WalkerSchema {
    has walker_type: type[WalkerArchetype],
        node_type: type[NodeArchetype],
        edge_type: type[EdgeArchetype],
        state_field: str,
        node_field: str,
        source: Path,
        source_sha256: str,
        entry_function: any,
        ptx: str,
        kernel_name: str,
        dtype: GpuScalarType = GpuScalarType.FLOAT64,
        graph_format: str = 'chain',
        node_fields: list[str] = [],
        node_objects: dict[str, type] = {},
        state_fields: list[str] = [],
        state_objects: dict[str, type] = {},
        emits_reports: bool = False;

    def field_paths -> list[str] {
        return self.node_fields or [self.node_field];
    }

    def state_paths -> list[str] {
        return self.state_fields or [self.state_field];
    }
}

obj PackedWalkerBatch {
    has walkers: list[WalkerArchetype],
        nodes: list[NodeArchetype],
        buffers: ChainBuffers | CsrBuffers,
        state_objects: list[dict[str, object]] = [];

    def memory_plan -> GpuMemoryPlan {
        if isinstance(self.buffers, CsrBuffers) {
            return with_report_plan(csr_memory_plan(
                len(self.nodes),
                len(self.buffers.targets),
                len(self.walkers),
                self.buffers.queue_capacity,
                node_field_count=len(self.buffers.columns()),
                state_field_count=len(self.buffers.initial_columns())
            ), self.buffers.reports);
        }
        return with_report_plan(make_memory_plan(
            len(self.nodes),
            len(self.walkers),
            node_field_count=len(self.buffers.columns()),
            state_field_count=len(self.buffers.initial_columns())
        ), self.buffers.reports);
    }
}

obj WalkerBatchResult {
    has values: list[float | int],
        status: list[int],
        memory: GpuMemoryPlan,
        gpu_executed: bool,
        gpu_name: str = '',
        cuda_driver_version: int = 0,
        fields: dict[str, list[float | int]] = {},
        reports: list[list[float | int]] = [];
}

def walker_schema(walker_type: type, graph_format: str = 'chain') -> WalkerSchema {
    import from jaclang.compiler.backends.native.ptx { compile_ptx_frontend }
    import from jaclang.compiler.backends.native.ptx_walker {
        select_chain_walkers,
        emit_chain_ptx
    }
    if graph_format not in ('chain', 'csr') {
        raise ValueError("GPU graph_format must be 'chain' or 'csr'");
    }
    if not isinstance(walker_type, type)
        or not issubclass(walker_type, WalkerArchetype) {
        raise TypeError("Expected a Jac walker class");
    }
    walker_class = cast(type[WalkerArchetype], walker_type);
    module = sys.modules.get(walker_class.__module__);
    source = Path(getattr(module, '__file__', ''));
    if source.suffix != '.jac'
        or not source.is_file()
        or getattr(module, walker_type.__name__, None) is not walker_type {
        raise ValueError(
            "GPU walkers must be top-level classes loaded from an available Jac source file"
        );
    }
    source = source.resolve();
    digest = hashlib.sha256(source.read_bytes()).hexdigest();
    spec = select_chain_walkers(
        compile_ptx_frontend(str(source)), [walker_type.__name__]
    )[0];
    node_type = getattr(module, spec.node_type);
    edge_type = getattr(module, spec.edge_type);
    funcs = walker_class._jac_entry_funcs_;
    if len(funcs) != 1
        or walker_class._jac_exit_funcs_
        or funcs[0].trigger is not node_type {
        raise ValueError(
            "Loaded walker event dispatch does not match the compiled GPU subset"
        );
    }
    if Path(funcs[0].func.__code__.co_filename).resolve() != source {
        raise ValueError(
            "Loaded walker ability does not belong to its Jac source file"
        );
    }
    if graph_format == 'csr' {
        import from jaclang.compiler.backends.native.ptx_csr { emit_csr_ptx }
        artifact = emit_csr_ptx([spec]);
    } else {
        artifact = emit_chain_ptx([spec]);
    }
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest {
        raise RuntimeError("Walker source changed during GPU compilation");
    }
    return WalkerSchema(
        walker_class,
        node_type,
        edge_type,
        spec.state_field,
        spec.node_field,
        source,
        digest,
        funcs[0].func,
        artifact.ptx,
        artifact.kernels[0]['name'],
        spec.dtype,
        graph_format,
        spec.field_paths(),
        {path: getattr(module, name) for (path, name) in spec.node_objects.items()},
        spec.state_paths(),
        {path: getattr(module, name) for (path, name) in spec.state_objects.items()},
        bool(spec.report_parameters())
    );
}

def check_private(anchor: any) {
    if anchor.destroyed
        or anchor.persistent
        or anchor.root is not None
        or anchor.access is not None {
        raise ValueError(
            "GPU batches currently require private, live, in-memory graph objects"
        );
    }
}

def float_value(value: any) -> float {
    if type(value) not in (int, float) {
        raise TypeError("GPU float fields must contain numeric scalar values");
    }
    return float(value);
}

def scalar_value(value: any, dtype: GpuScalarType) -> float | int {
    if dtype == GpuScalarType.FLOAT64 {
        return float_value(value);
    }
    if type(value) is not int {
        raise TypeError("GPU int fields must contain integers (not bool or float)");
    }
    if not -(2 ** 63) <= value < 2 ** 63 {
        raise OverflowError("GPU int fields must fit signed int64");
    }
    return cast(int, value);
}

def field_parent(objects: dict[str, object], path: str) -> tuple[object, str] {
    parts = path.rsplit(".", 1);
    return (objects[parts[0]] if len(parts) == 2 else objects[""], parts[-1]);
}

def data_objects(instance: object, types: dict[str, type]) -> dict[str, object] {
    objects = {"": instance};
    for (path, expected_type) in types.items() {
        (parent, name) = field_parent(objects, path);
        value = getattr(parent, name);
        if type(value) is not expected_type {
            raise TypeError(
                f"GPU object {path} must have exactly type {expected_type.__name__}"
            );
        }
        objects[path] = value;
    }
    return objects;
}

def check_finite_chains(links: list[int]) {
    marks = [0] * len(links);
    for start in range(len(links)) {
        current = start;
        path: list[int] = [];
        while current != -1 and marks[current] == 0 {
            marks[current] = 1;
            path.append(current);
            current = links[current];
        }
        if current != -1 and marks[current] == 1 {
            raise ValueError("GPU chain batch contains a cycle");
        }
        for idx in path {
            marks[idx] = 2;
        }
    }
}

def pack_walkers(
    schema: WalkerSchema,
    walkers: Sequence[object],
    starts: Sequence[object],
    queue_capacity: int = 1024,
    max_visits: int = 1000000,
    report_capacity: int = 1024
) -> PackedWalkerBatch {
    import from jaclang.runtime.graph_query { GraphQuery, QHop }
    import from jaclang.runtime.graph_walk { walk }
    import from jaclang.runtime.osp_kernel { scope_of }
    if schema.graph_format == 'csr' {
        check_csr_limits(queue_capacity, max_visits);
    }
    if len(walkers) != len(starts) {
        raise ValueError("Each walker must have exactly one starting node (or None)");
    }
    if len({id(w) for w in walkers}) != len(walkers) {
        raise ValueError("The same walker instance cannot occupy multiple GPU lanes");
    }
    initial: list[list[float | int]] = [[] for path in schema.state_paths()];
    state_objects: list[dict[str, object]] = [];
    state_owners: set[int] = set();
    typed_walkers: list[WalkerArchetype] = [];
    for w in walkers {
        if not isinstance(w, WalkerArchetype) or type(w) is not schema.walker_type {
            raise TypeError(
                "A GPU batch requires instances of exactly one compiled walker type"
            );
        }
        anch = w.__jac__;
        check_private(anch);
        if scope_of(w) is not None
            or anch.next
            or anch.ignores
            or anch.disengaged
            or anch.path {
            raise ValueError(
                "GPU walkers cannot have an active traversal, queued work, or path"
            );
        }
        objects = data_objects(w, schema.state_objects);
        for path in schema.state_objects {
            key = id(objects[path]);
            if key in state_owners {
                raise ValueError(
                    f"GPU walker object {path} must belong to exactly one state path and walker"
                );
            }
            state_owners.add(key);
        }
        for (path, column) in zip(schema.state_paths(), initial) {
            (parent, name) = field_parent(objects, path);
            column.append(scalar_value(getattr(parent, name), schema.dtype));
        }
        state_objects.append(objects);
        typed_walkers.append(w);
    }
    nodes: list[NodeArchetype] = [];
    slots: dict[any, int] = {};
    def slot(nd: object) -> int {
        if nd is None {
            return -1;
        }
        if not isinstance(nd, NodeArchetype) or type(nd) is not schema.node_type {
            raise TypeError("Reachable node type does not match the compiled walker");
        }
        node_anchor = nd.__jac__;
        check_private(node_anchor);
        key = anchor_key(node_anchor);
        if key not in slots {
            slots[key] = len(nodes);
            nodes.append(nd);
        }
        return slots[key];
    }
    heads = [slot(nd) for nd in starts];
    paths = schema.field_paths();
    columns: list[list[float | int]] = [[] for path in paths];
    object_owners: dict[int, int] = {};
    links: list[int] = [];
    offsets = [0];
    targets: list[int] = [];
    seen: set[int] = set();
    idx = 0;
    while idx < len(nodes) {
        nd = nodes[idx];
        objects = data_objects(nd, schema.node_objects);
        for path in schema.node_objects {
            key = id(objects[path]);
            if key in state_owners {
                raise ValueError(
                    f"GPU nested object {path} is shared by a node and walker"
                );
            }
            if key in object_owners and object_owners[key] != idx {
                raise ValueError(
                    f"GPU nested object {path} is shared by different nodes"
                );
            }
            object_owners[key] = idx;
        }
        for (path, column) in zip(paths, columns) {
            (parent, name) = field_parent(objects, path);
            column.append(scalar_value(getattr(parent, name), schema.dtype));
        }
        query = GraphQuery(
            [nd], hops=[QHop(dir=2, `edge=schema.edge_type)], edges_only=True
        );
        pairs = walk([nd.__jac__], query, 1, False);
        if schema.graph_format == 'chain' and len(pairs) > 1 {
            raise ValueError(
                "GPU chain nodes may have at most one outgoing selected edge"
            );
        }
        successor = -1;
        seen.clear();
        for (other, connection) in pairs {
            assert connection is not None;
            check_private(connection);
            if type(connection.archetype) is not schema.edge_type
                or connection.is_undirected {
                raise ValueError(
                    "GPU walkers require the exact declared, directed edge type"
                );
            }
            if not isinstance(other, NodeAnchor) {
                raise TypeError("GPU walkers must visit nodes");
            }
            target = slot(other.archetype);

            if schema.graph_format == 'csr' {
                if target not in seen {
                    targets.append(target);
                    seen.add(target);
                }
            } else {
                successor = target;
            }
        }
        if schema.graph_format == 'csr' {
            offsets.append(len(targets));
        } else {
            links.append(successor);
        }
        idx += 1;
    }
    reports = report_buffers(len(walkers), report_capacity, schema.dtype) if schema.emits_reports else None;
    if schema.graph_format == 'csr' {
        buffers = csr_buffers(
            columns[0], offsets, targets, heads, initial[0], schema.dtype,
            queue_capacity, max_visits, extra_values=columns[1:], extra_initial=initial[1:]
        );
        buffers.reports = reports;
        return PackedWalkerBatch(typed_walkers, nodes, buffers, state_objects);
    }
    check_finite_chains(links);
    buffers_chain = chain_buffers(
        columns[0], links, heads, initial[0], schema.dtype,
        extra_values=columns[1:], extra_initial=initial[1:]
    );
    buffers_chain.reports = reports;
    return PackedWalkerBatch(typed_walkers, nodes, buffers_chain, state_objects);
}

def publish_results(
    schema: WalkerSchema,
    batch: PackedWalkerBatch,
    plan: GpuMemoryPlan,
    gpu_name: str,
    driver_version: int
) -> WalkerBatchResult {
    status = cast(list[int], batch.buffers.status.tolist());
    if any(status) {
        if 7 in status {
            raise RuntimeError("GPU report capacity exceeded; increase report_capacity. No walker state or reports published");
        }
        if 4 in status {
            raise ZeroDivisionError(
                "GPU integer modulo by zero; no walker fields updated"
            );
        }
        if 3 in status {
            raise OverflowError(
                "GPU integer arithmetic overflow; no walker fields updated"
            );
        }
        if isinstance(batch.buffers, CsrBuffers) {
            if 6 in status {
                raise RuntimeError(
                    "GPU CSR queue capacity exceeded; increase queue_capacity. No walker fields updated"
                );
            }
            if 2 in status {
                raise RuntimeError(
                    "GPU CSR visit limit exceeded (possibly a cycle); no walker fields updated"
                );
            }
        }
        failed = [
            (i, code)
            for (i, code) in enumerate(status)
            if code
        ];
        raise RuntimeError(
            f"GPU walker batch failed; no walker fields updated. Lane/status: {failed[:8]}"
        );
    }
    paths = schema.state_paths();
    initials = batch.buffers.initial_columns();
    outputs = batch.buffers.result_columns();
    if len(initials) != len(paths)
        or len(outputs) != len(paths)
        or len(status) != len(batch.walkers)
        or len(batch.state_objects) != len(batch.walkers)
        or any(len(column) != len(batch.walkers) for column in [*initials, *outputs]) {
        raise ValueError("GPU walker result columns do not match the packed batch");
    }
    writes: list[tuple[object, str, float | int]] = [];
    code = '=q' if schema.dtype == GpuScalarType.INT64 else '=d';
    for (lane, w) in enumerate(batch.walkers) {
        check_private(w.__jac__);
        objects = data_objects(w, schema.state_objects);
        if any(
            objects[path] is not original
            for (path, original) in batch.state_objects[lane].items()
        ) {
            raise RuntimeError(
                "Walker nested object changed during the GPU call; no results published"
            );
        }
        for (path, initial, output) in zip(paths, initials, outputs) {
            (parent, name) = field_parent(objects, path);
            current = scalar_value(getattr(parent, name), schema.dtype);
            if struct.pack(code, current) != struct.pack(code, initial[lane]) {
                raise RuntimeError(
                    "Walker state changed during the GPU call; no results published"
                );
            }
            writes.append((parent, name, output[lane]));
        }
    }
    fields = {
        path: cast(list[float | int], column.tolist())
        for (path, column) in zip(paths, outputs)
    };
    reports: list[list[float | int]] = [[] for w in batch.walkers];
    report_data = batch.buffers.reports;
    if schema.emits_reports != (report_data is not None) {
        raise ValueError("GPU report buffers do not match the compiled walker");
    }
    if report_data is not None {
        count = len(batch.walkers);
        if len(report_data.counts) != count or len(report_data.values) != count * report_data.capacity {
            raise ValueError("GPU report buffers do not match the packed batch");
        }
        for (lane, length) in enumerate(report_data.counts) {
            if length > report_data.capacity {
                raise RuntimeError("Invalid GPU report count; no results published");
            }
            reports[lane] = [report_data.values[slot * count + lane] for slot in range(length)];
        }
    }
    for (parent, name, value) in writes {
        setattr(parent, name, value);
    }
    for (w, emitted) in zip(batch.walkers, reports) {
        w.reports = emitted;
    }
    return WalkerBatchResult(
        fields[paths[0]],
        status,
        plan,
        bool(batch.walkers),
        gpu_name,
        driver_version,
        fields,
        reports
    );
}

obj GpuWalkerRuntime {
    has walker_type: type,
        device: int = 0,
        block_size: int = 128,
        graph_format: str = 'chain',
        queue_capacity: int = 1024,
        max_visits: int = 1000000,
        report_capacity: int = 1024,
        schema: WalkerSchema postinit,
        session: CudaSession | None = None,
        owner_thread: int = 0,
        closed: bool = False;

    def postinit {
        check_report_capacity(self.report_capacity);
        self.owner_thread = get_ident();
        if self.graph_format == 'csr' {
            check_csr_limits(self.queue_capacity, self.max_visits);
        }
        self.schema = walker_schema(self.walker_type, self.graph_format);
    }

    def check_open {
        if self.closed or get_ident() != self.owner_thread {
            raise RuntimeError("Use an open GPU runtime on its creating thread");
        }
        if hashlib.sha256(self.schema.source.read_bytes()).hexdigest()
            != self.schema.source_sha256 {
            raise RuntimeError(
                "Walker source changed; reload the module and create a new GPU runtime"
            );
        }
        funcs = self.schema.walker_type._jac_entry_funcs_;
        if len(funcs) != 1 or funcs[0].func is not self.schema.entry_function {
            raise RuntimeError("Walker event dispatch changed after GPU preparation");
        }
    }

    def prepare(
        walkers: Sequence[object], starts: Sequence[object]
    ) -> PackedWalkerBatch {
        self.check_open();
        return pack_walkers(
            self.schema, walkers, starts, self.queue_capacity, self.max_visits, self.report_capacity
        );
    }

    def run_walkers(
        walkers: Sequence[object], starts: Sequence[object]
    ) -> WalkerBatchResult {
        batch = self.prepare(walkers, starts);
        if not walkers {
            plan = batch.memory_plan()
                if self.session is None
                else self.session.plan_for(batch.buffers);
            return WalkerBatchResult(
                [],
                [],
                plan,
                False,
                fields={path: [] for path in self.schema.state_paths()}
            );
        }
        if self.session is None {
            self.session = CudaSession(
                self.schema.ptx,
                self.schema.kernel_name,
                self.device,
                self.block_size,
                graph_format=self.schema.graph_format,
                node_field_count=len(self.schema.field_paths()),
                state_field_count=len(self.schema.state_paths()),
                emits_reports=self.schema.emits_reports
            );
        }
        plan = self.session.execute(batch.buffers);
        self.check_open();
        return publish_results(
            self.schema, batch, plan, self.session.gpu_name, self.session.driver_version
        );
    }

    def close {
        if self.closed {
            return;
        }
        if get_ident() != self.owner_thread {
            raise RuntimeError("Close the GPU runtime on its creating thread");
        }
        if self.session is not None {
            self.session.close();
        }
        self.closed = True;
    }

    def __enter__ -> GpuWalkerRuntime {
        self.check_open();
        return self;
    }

    def __exit__(exc_type: any, exc: any, tb: any) {
        self.close();
    }
}

def run_walkers(
    walkers: Sequence[object],
    starts: Sequence[object],
    device: int = 0,
    graph_format: str = 'chain',
    queue_capacity: int = 1024,
    max_visits: int = 1000000,
    report_capacity: int = 1024
) -> WalkerBatchResult {
    check_report_capacity(report_capacity);
    if graph_format not in ('chain', 'csr') {
        raise ValueError("GPU graph_format must be 'chain' or 'csr'");
    }
    if graph_format == 'csr' {
        check_csr_limits(queue_capacity, max_visits);
    }
    if not walkers {
        if starts {
            raise ValueError("Each walker must have exactly one starting node");
        }
        plan = csr_memory_plan(0, 0, 0, queue_capacity)
            if graph_format == 'csr'
            else make_memory_plan(0, 0);
        return WalkerBatchResult([], [], plan, False);
    }
    with GpuWalkerRuntime(
        type(walkers[0]),
        device=device,
        graph_format=graph_format,
        queue_capacity=queue_capacity,
        max_visits=max_visits,
        report_capacity=report_capacity
    ) as runtime {
        return runtime.run_walkers(walkers, starts);
    }
}
