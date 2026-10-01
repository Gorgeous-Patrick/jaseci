import from jaclang.compiler.backends.native.llvm { ir }
import jaclang.compiler.backends.native.llvm.binding as llvm;
import from jaclang.compiler.backends.native.ptx {
    PtxArtifact,
    emit_ptx_artifact,
    ptx_target,
    thread_index
}
import from jaclang.compiler.backends.native.ptx_walker { ChainWalker }
import from jaclang.runtime.gpu_memory { GpuScalarType }

def csr_metadata(spec: ChainWalker) -> dict[str, any] {
    result = spec.metadata();
    result['name'] = f"jac_{spec.name}_csr_batch";
    result['kind'] = 'csr_walker';
    result['parameters'] = spec.field_parameters()
        + [
            {"name": name, "dtype": dtype, "length": length, "access": access}
            for (name, dtype, length, access) in (
                ('offsets', 'int64', 'node_count + 1', 'read'),
                ('targets', 'int64', 'edge_count', 'read'),
                ('heads', 'int64', 'walker_count', 'read'),
                ('initial_total', spec.dtype.value, 'walker_count', 'read'),
                ('results', spec.dtype.value, 'walker_count', 'write'),
                ('status', 'uint32', 'walker_count', 'write'),
                ('queue', 'int64', 'queue_capacity * walker_count', 'scratch')
            )
        ]
        + [
            {"name": name, "dtype": 'uint64'}
            for name in (
                'node_count',
                'edge_count',
                'walker_count',
                'queue_capacity',
                'max_visits'
            )
        ];
    result['status_codes'] = {
        '0': 'success',
        '1': 'invalid_node_index',
        '2': 'visit_limit_exceeded',
        '3': 'integer_overflow',
        '4': 'integer_modulo_by_zero',
        '5': 'invalid_csr_offsets',
        '6': 'queue_capacity_exceeded'
    };
    result['graph_contract'] = 'read-only typed CSR adjacency; unique targets per row in Jac node-query order';
    result['traversal'] = 'FIFO visits; repeated arrivals execute again; bounded queue and visit count';
    result['layout'] = 'SoA with remapped rows, targets and heads; queue[slot * walker_count + lane]';
    return result;
}

def build_csr_module(
    walkers: list[ChainWalker], target: llvm.TargetMachine, device: bool = True
) -> llvm.ModuleRef {
    module = ir.Module(name='jac_gpu_csr_walkers');
    module.triple = target.triple;
    module.data_layout = str(target.target_data);
    for spec in walkers {
        lower_csr(module, spec, device);
    }
    compiled = llvm.parse_assembly(str(module));
    compiled.verify();
    return compiled;
}

def lower_csr(module: ir.Module, spec: ChainWalker, device: bool) {
    (i32, i64) = (ir.IntType(32), ir.IntType(64));
    scalar = i64 if spec.dtype == GpuScalarType.INT64 else ir.DoubleType();
    space = 1 if device else 0;
    field_count = len(spec.field_paths());
    signature = [
        t.as_pointer(addrspace=space)
        for t in [scalar] * field_count + [i64, i64, i64, scalar, scalar, i32, i64]
    ]
        + [i64] * (5 if device else 6);
    suffix = 'batch' if device else 'lane';
    fn = ir.Function(
        module,
        ir.FunctionType(ir.VoidType(), signature),
        name=f'jac_{spec.name}_csr_{suffix}'
    );
    if device {
        fn.calling_convention = 'ptx_kernel';
    }
    for (arg, name) in zip(
        fn.args,
        [p['name'] for p in spec.field_parameters()]
            + [
                'offsets',
                'targets',
                'heads',
                'initial_total',
                'results',
                'status',
                'queue',
                'node_count',
                'edge_count',
                'walker_count',
                'queue_capacity',
                'max_visits',
                'index'
            ]
    ) {
        arg.name = name;
    }
    values = fn.args[:field_count];
    (
        offsets,
        targets,
        heads,
        initial,
        output,
        status,
        queue,
        node_count,
        edge_count,
        count,
        capacity,
        max_visits
    ) = fn.args[field_count:field_count + 12];
    entry_bb = fn.append_basic_block('entry');
    start = fn.append_basic_block('start');
    init = fn.append_basic_block('queue.init');
    ready = fn.append_basic_block('queue.ready');
    check = fn.append_basic_block('queue.check');
    pop = fn.append_basic_block('queue.pop');
    limit = fn.append_basic_block('visit.limit');
    body = fn.append_basic_block('ability');
    room = fn.append_basic_block('queue.room');
    edges = fn.append_basic_block('edges.check');
    edge_body = fn.append_basic_block('edge.read');
    append = fn.append_basic_block('queue.append');
    advance = fn.append_basic_block('advance');
    finish = fn.append_basic_block('finish');
    bad_index = fn.append_basic_block('invalid.node');
    visit_limit = fn.append_basic_block('visit.limit.exceeded');
    overflow = fn.append_basic_block('integer.overflow');
    zero_divisor = fn.append_basic_block('integer.modulo.zero');
    bad_row = fn.append_basic_block('invalid.csr.offsets');
    queue_full = fn.append_basic_block('queue.capacity.exceeded');
    done = fn.append_basic_block('done');
    b = ir.IRBuilder(entry_bb);
    (zero, one) = (ir.Constant(i64, 0), ir.Constant(i64, 1));
    index = thread_index(module, b) if device else fn.args[-1];
    b.cbranch(b.icmp_unsigned('<', index, count), start, done);
    b.position_at_end(start);
    head = b.load(b.gep(heads, [index]));
    seed = b.load(b.gep(initial, [index]));
    b.cbranch(b.icmp_signed('==', head, ir.Constant(i64, -1)), finish, init);
    b.position_at_end(init);
    b.cbranch(b.icmp_unsigned('>', capacity, zero), ready, queue_full);
    b.position_at_end(ready);
    b.store(head, b.gep(queue, [index]));
    first_tail = b.select(b.icmp_unsigned('==', capacity, one), zero, one);
    b.branch(check);
    b.position_at_end(check);
    read_pos = b.phi(i64, name='read.pos');
    write_pos = b.phi(i64, name='write.pos');
    pending = b.phi(i64, name='pending');
    steps = b.phi(i64, name='steps');
    total = b.phi(scalar, name=spec.state_field);
    for (phi, value) in (
        (read_pos, zero),
        (write_pos, first_tail),
        (pending, one),
        (steps, zero),
        (total, seed)
    ) {
        phi.add_incoming(value, ready);
    }
    b.cbranch(b.icmp_unsigned('==', pending, zero), finish, pop);
    b.position_at_end(pop);
    current = b.load(b.gep(queue, [b.add(b.mul(read_pos, count), index)]));
    increment = b.add(read_pos, one);
    next_read = b.select(b.icmp_unsigned('==', increment, capacity), zero, increment);
    remaining = b.sub(pending, one);
    valid = b.and_(
        b.icmp_signed('>=', current, zero), b.icmp_unsigned('<', current, node_count)
    );
    b.cbranch(valid, limit, bad_index);
    b.position_at_end(limit);
    b.cbranch(b.icmp_unsigned('<', steps, max_visits), body, visit_limit);
    b.position_at_end(body);
    node_value = [
        b.load(b.gep(column, [current]), name=path)
        for (column, path) in zip(values, spec.field_paths())
    ];
    updated = spec.update.lower(b, total, node_value, overflow, zero_divisor);
    begin = b.load(b.gep(offsets, [current]));
    end = b.load(b.gep(offsets, [b.add(current, one)]));
    row_valid = b.and_(
        b.icmp_signed('>=', begin, zero),
        b.and_(
            b.icmp_unsigned('<=', begin, end), b.icmp_unsigned('<=', end, edge_count)
        )
    );
    b.cbranch(row_valid, room, bad_row);
    b.position_at_end(room);
    degree = b.sub(end, begin);
    b.cbranch(
        b.icmp_unsigned('<=', degree, b.sub(capacity, remaining)), edges, queue_full
    );
    b.position_at_end(edges);
    edge_cursor = b.phi(i64, name='edge');
    tail = b.phi(i64, name='tail');
    edge_cursor.add_incoming(begin, room);
    tail.add_incoming(write_pos, room);
    b.cbranch(b.icmp_unsigned('<', edge_cursor, end), edge_body, advance);
    b.position_at_end(edge_body);
    target = b.load(b.gep(targets, [edge_cursor]));
    valid_target = b.and_(
        b.icmp_signed('>=', target, zero), b.icmp_unsigned('<', target, node_count)
    );
    b.cbranch(valid_target, append, bad_index);
    b.position_at_end(append);
    b.store(target, b.gep(queue, [b.add(b.mul(tail, count), index)]));
    increment_tail = b.add(tail, one);
    next_tail = b.select(
        b.icmp_unsigned('==', increment_tail, capacity), zero, increment_tail
    );
    next_edge = b.add(edge_cursor, one);
    b.branch(edges);
    edge_cursor.add_incoming(next_edge, append);
    tail.add_incoming(next_tail, append);
    b.position_at_end(advance);
    next_pending = b.add(remaining, degree);
    next_step = b.add(steps, one);
    b.branch(check);
    for (phi, value) in (
        (read_pos, next_read),
        (write_pos, tail),
        (pending, next_pending),
        (steps, next_step),
        (total, updated)
    ) {
        phi.add_incoming(value, advance);
    }
    b.position_at_end(finish);
    final = b.phi(scalar);
    final.add_incoming(seed, start);
    final.add_incoming(total, check);
    b.store(final, b.gep(output, [index]));
    b.store(ir.Constant(i32, 0), b.gep(status, [index]));
    b.branch(done);
    for (block, code) in (
        (bad_index, 1),
        (visit_limit, 2),
        (overflow, 3),
        (zero_divisor, 4),
        (bad_row, 5),
        (queue_full, 6)
    ) {
        b.position_at_end(block);
        b.store(ir.Constant(i32, code), b.gep(status, [index]));
        b.branch(done);
    }
    b.position_at_end(done);
    b.ret_void();
}

def emit_csr_ptx(walkers: list[ChainWalker]) -> PtxArtifact {
    target = ptx_target();
    artifact = emit_ptx_artifact(
        build_csr_module(walkers, target),
        target,
        [csr_metadata(spec) for spec in walkers]
    );
    artifact.format = 'jac-ptx-csr-v1';
    artifact.argument_order = 'values, offsets, targets, heads, initial_total, results, status, queue, node_count, edge_count, walker_count, queue_capacity, max_visits';
    if any(len(spec.field_paths()) > 1 for spec in walkers) {
        artifact.format = 'jac-ptx-csr-v2';
        artifact.argument_order = "node field pointers, offsets, targets, heads, initial_total, results, status, queue, node_count, edge_count, walker_count, queue_capacity, max_visits; exact order in each kernel's parameters";
    }
    return artifact;
}
