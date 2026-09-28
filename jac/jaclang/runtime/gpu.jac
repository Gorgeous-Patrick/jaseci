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
    GpuMemoryPlan,
    chain_buffers,
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
        kernel_name: str;
}

obj PackedWalkerBatch {
    has walkers: list[WalkerArchetype],
        nodes: list[NodeArchetype],
        buffers: ChainBuffers;

    def memory_plan -> GpuMemoryPlan {
        return make_memory_plan(len(self.nodes), len(self.walkers));
    }
}

obj WalkerBatchResult {
    has values: list[float],
        status: list[int],
        memory: GpuMemoryPlan,
        gpu_executed: bool,
        gpu_name: str = '',
        cuda_driver_version: int = 0;
}

def walker_schema(walker_type: type) -> WalkerSchema {
    import from jaclang.compiler.backends.native.ptx { compile_ptx_frontend }
    import from jaclang.compiler.backends.native.ptx_walker {
        select_chain_walkers,
        emit_chain_ptx
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
    artifact = emit_chain_ptx([spec]);
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
        artifact.kernels[0]['name']
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
    schema: WalkerSchema, walkers: Sequence[object], starts: Sequence[object]
) -> PackedWalkerBatch {
    import from jaclang.runtime.graph_query { GraphQuery, QHop }
    import from jaclang.runtime.graph_walk { walk }
    import from jaclang.runtime.osp_kernel { scope_of }
    if len(walkers) != len(starts) {
        raise ValueError("Each walker must have exactly one starting node (or None)");
    }
    if len({id(w) for w in walkers}) != len(walkers) {
        raise ValueError("The same walker instance cannot occupy multiple GPU lanes");
    }
    initial: list[float] = [];
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
            or anch.path
            or w.reports {
            raise ValueError(
                "GPU walkers cannot have an active traversal, queued work, path, or reports"
            );
        }
        initial.append(float_value(getattr(w, schema.state_field)));
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
    values: list[float] = [];
    links: list[int] = [];
    idx = 0;
    while idx < len(nodes) {
        nd = nodes[idx];
        values.append(float_value(getattr(nd, schema.node_field)));
        query = GraphQuery(
            [nd], hops=[QHop(dir=2, `edge=schema.edge_type)], edges_only=True
        );
        pairs = walk([nd.__jac__], query, 1, False);
        if len(pairs) > 1 {
            raise ValueError(
                "GPU chain nodes may have at most one outgoing selected edge"
            );
        }
        successor: NodeArchetype | None = None;
        if pairs {
            (other, connection) = pairs[0];
            assert connection is not None;
            check_private(connection);
            if type(connection.archetype) is not schema.edge_type
                or connection.is_undirected {
                raise ValueError(
                    "GPU chains require the exact declared, directed edge type"
                );
            }
            if not isinstance(other, NodeAnchor) {
                raise TypeError("GPU chains must visit nodes");
            }
            successor = other.archetype;
        }
        links.append(slot(successor));
        idx += 1;
    }
    check_finite_chains(links);
    return PackedWalkerBatch(
        typed_walkers, nodes, chain_buffers(values, links, heads, initial)
    );
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
        failed = [
            (i, code)
            for (i, code) in enumerate(status)
            if code
        ];
        raise RuntimeError(
            f"GPU walker batch failed; no walker fields updated. Lane/status: {failed[:8]}"
        );
    }
    for (w, initial) in zip(batch.walkers, batch.buffers.initial) {
        check_private(w.__jac__);
        current = float_value(getattr(w, schema.state_field));
        if struct.pack('=d', current) != struct.pack('=d', initial) {
            raise RuntimeError(
                "Walker state changed during the GPU call; no results published"
            );
        }
    }
    values = cast(list[float], batch.buffers.results.tolist());
    for (w, value) in zip(batch.walkers, values) {
        setattr(w, schema.state_field, value);
    }
    return WalkerBatchResult(
        values, status, plan, bool(batch.walkers), gpu_name, driver_version
    );
}

obj GpuWalkerRuntime {
    has walker_type: type,
        device: int = 0,
        block_size: int = 128,
        schema: WalkerSchema postinit,
        session: CudaSession | None = None,
        owner_thread: int = 0,
        closed: bool = False;

    def postinit {
        self.owner_thread = get_ident();
        self.schema = walker_schema(self.walker_type);
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
        return pack_walkers(self.schema, walkers, starts);
    }

    def run_walkers(
        walkers: Sequence[object], starts: Sequence[object]
    ) -> WalkerBatchResult {
        batch = self.prepare(walkers, starts);
        if not walkers {
            plan = batch.memory_plan()
                if self.session is None
                else make_memory_plan(
                    0,
                    0,
                    self.session.graph_arena.capacity,
                    self.session.walker_arena.capacity
                );
            return WalkerBatchResult([], [], plan, False);
        }
        if self.session is None {
            self.session = CudaSession(
                self.schema.ptx, self.schema.kernel_name, self.device, self.block_size
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
    walkers: Sequence[object], starts: Sequence[object], device: int = 0
) -> WalkerBatchResult {
    if not walkers {
        if starts {
            raise ValueError("Each walker must have exactly one starting node");
        }
        return WalkerBatchResult([], [], make_memory_plan(0, 0), False);
    }
    with GpuWalkerRuntime(type(walkers[0]), device=device) as runtime {
        return runtime.run_walkers(walkers, starts);
    }
}
