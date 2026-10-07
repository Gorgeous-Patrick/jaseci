"""Named-cursor GPU ABI and conservative batch BFS layout prediction.

Python host code builds LLVM for host JIT and NVPTX from the same control flow.
No Python traversal is substituted for device execution.
"""
from __future__ import annotations
from array import array
from collections import deque
from dataclasses import dataclass
import ctypes as c
import hashlib
import random
from time import perf_counter

class CursorFields(list):

    def __init__(self, paths, names):
        super().__init__(paths)
        self.cursor_names = names

@dataclass
class CursorSpec:
    base: object
    cursor_names: list[str]
    edges: list[str | None]
    guards: list[int | None]
    conditional: bool

    def __getattr__(self, name):
        return getattr(self.base, name)

    def metadata(self):
        result = self.base.metadata()
        k = len(self.cursor_names)
        params = self.base.field_parameters()
        params += [dict(name=name, dtype='int64', length=length, access=access) for name, length, access in (('type_tags', 'node_count', 'read'), ('offsets', f'{k} * (node_count + 1)', 'read'), ('targets', 'edge_count', 'read'), ('heads', f'{k} * walker_count', 'read'), ('seed_counts', f'{k} * walker_count', 'read'))]
        params += self.base.state_parameters() + self.base.state_parameters(True)
        params += [dict(name='status', dtype='uint32', length='walker_count', access='write'), dict(name='queue', dtype='int64', length=f'{k} * queue_capacity * walker_count', access='read_write')]
        params += [dict(name=name, dtype='uint64') for name in ('node_count', 'edge_count', 'walker_count', 'queue_capacity', 'max_visits')]
        params += self.base.report_parameters()
        result.update(name=f'jac_{self.name}_cursors_batch', kind='cursor_walker', parameters=params, cursors=[dict(name=n, trigger=self.node_type, edge=e) for n, e in zip(self.cursor_names, self.edges)], joint_condition='all current type tags match; one fresh arrival per channel per round', graph_contract='ordered per-channel CSR; identity-deduplicated storage, repeated FIFO arrivals preserved', layout='node SoA; heads[cursor * lanes + lane]; queue[(cursor * capacity + slot) * lanes + lane]', prediction='per-cursor multi-source discovery BFS; conditional visits conservatively include selected relations', status_codes={'0': 'success', '1': 'invalid_node_index', '2': 'round_limit_exceeded', '3': 'integer_overflow', '4': 'integer_modulo_by_zero', '5': 'invalid_csr_offsets', '6': 'queue_capacity_exceeded', '7': 'report_capacity_exceeded'})
        return result

def select_cursor_walker(module, arch):
    import jaclang.compiler.frontend.unitree as u
    from jaclang.compiler.backends.native import ptx_walker as w
    from jaclang.runtime.constants import EdgeDir
    from jaclang.runtime.gpu_memory import GpuScalarType as T
    archs = {a.name.value: a for a in module.body if isinstance(a, u.Archetype)}
    w.plain_archetype(arch)
    decls = [s for s in arch.body if isinstance(s, u.CursorDecl)]
    abilities = arch.get_methods()
    if len(decls) != 1 or len(abilities) != 1 or any((not isinstance(s, (u.CursorDecl, u.ArchHas, u.Ability)) for s in arch.body)):
        w.reject(arch, 'GPU named cursors require one local joint entry ability')
    names = list(decls[0].names)
    ability = abilities[0]
    sig = ability.signature
    if not isinstance(sig, u.EventSignature) or sig.event.value != 'entry' or set(sig.cursor_names) != set(names) or any((ability.is_async, ability.is_static, ability.is_classmethod, ability.is_override, ability.is_abstract, ability.decorators, ability.type_params)):
        w.reject(ability, 'GPU named cursors require a plain synchronous joint entry ability')
    triggers = list(sig.arch_tag_info.values)
    nds = [archs.get(t.value) if isinstance(t, u.Name) else None for t in triggers]
    if not nds or any((nd is None or nd.arch_kind != 'node' for nd in nds)) or any((nd is not nds[0] for nd in nds)):
        w.reject(sig, 'GPU named cursors currently require the same explicit local node type in all channels; heterogeneous triggers are unsupported')
    nd = nds[0]
    w.plain_archetype(nd)
    states = w.project_fields(arch, archs)
    projection = w.project_fields(nd, archs, states.dtype)
    dtype = projection.dtype if states.dtype == T.BOOL else states.dtype
    paths = ['.'.join((f.name.value for f in path)) for path in projection.fields]
    state_paths = ['.'.join((f.name.value for f in path)) for path in states.fields]
    defaults = [w.literal_default(path[0], w.field_dtype(path)) if len(path) == 1 else None for path in states.fields]
    fields = CursorFields(projection.fields * len(names), [n for n in names for _ in projection.fields])
    locals_ = {}
    updates, edges, guards = ([], [None] * len(names), [None] * len(names))
    seen = set()
    conditional = False

    def visit(stmt, condition=None):
        nonlocal conditional
        idx = names.index(stmt.cursor_name) if stmt.cursor_name in names else -1
        query = stmt.target
        if idx < 0 or idx in seen or stmt.else_body is not None or (stmt.insert_loc is not None) or (not isinstance(query, u.EdgeRefTrailer)) or query.edges_only or query.is_async or (len(query.chain) != 1) or (not isinstance(query.chain[0], u.EdgeOpRef)):
            w.reject(stmt, 'GPU cursor visits allow at most one implicit outgoing typed query per channel; insertion, visit-else and explicit receivers are unsupported')
        hop = query.chain[0]
        filt = hop.filter_cond
        if hop.edge_dir != EdgeDir.OUT or filt is None or filt.compares or (not isinstance(filt.f_type, u.Name)):
            w.reject(stmt, 'GPU cursor visits require outgoing edge types without filters')
        edge = archs.get(filt.f_type.value)
        if edge is None or edge.arch_kind != 'edge':
            w.reject(stmt, 'GPU cursor visits require local edge types')
        w.plain_archetype(edge)
        if edge.body:
            w.reject(edge, 'GPU cursor edge types cannot have fields or behavior')
        seen.add(idx)
        edges[idx] = edge.name.value
        if condition is not None:
            conditional = True
            key = f'$visit{idx}'
            slot = len(states.fields) + len(locals_)
            locals_[key] = w.ChainExpr('state', state_index=slot, dtype=T.BOOL)
            updates.append(w.StateUpdate(w.chain_condition(condition, states.fields, fields, dtype, locals_), target=slot))
            guards[idx] = slot
    for stmt in ability.body:
        if isinstance(stmt, u.VisitStmt):
            visit(stmt)
        elif isinstance(stmt, u.IfStmt) and (not stmt.is_comptime) and (stmt.else_body is None) and (len(stmt.body) == 1) and isinstance(stmt.body[0], u.VisitStmt):
            visit(stmt.body[0], stmt.condition)
        else:
            updates.append(w.chain_update(stmt, states.fields, fields, dtype, locals_))
    updates = [w.StateUpdate(w.ChainExpr('constant', value=0, dtype=v.dtype), target=v.state_index) for v in sorted(locals_.values(), key=lambda v: v.state_index)] + updates
    base = w.ChainWalker(arch.name.value, nd.name.value, next((e for e in edges if e), ''), paths[0], state_paths[0], defaults[0], updates, dtype, paths, projection.objects, state_paths, states.objects, defaults, [w.field_dtype(p) for p in projection.fields], [w.field_dtype(p) for p in states.fields])
    return CursorSpec(base, names, edges, guards, conditional)

def build_cursor_module(specs, target, device=True):
    from jaclang.compiler.backends.native.llvm import ir, binding as llvm
    module = ir.Module(name='jac_gpu_named_cursors')
    module.triple, module.data_layout = (target.triple, str(target.target_data))
    for spec in specs:
        lower_cursor(module, spec, device)
    compiled = llvm.parse_assembly(str(module))
    compiled.verify()
    return compiled

def lower_cursor(module, spec, device):
    from jaclang.compiler.backends.native.llvm import ir
    from jaclang.compiler.backends.native.ptx import thread_index
    from jaclang.compiler.backends.native.ptx_walker import storage_type, load_field, store_field, lower_updates, value_type, has_reports, ReportOutput
    i64, i32 = (ir.IntType(64), ir.IntType(32))
    k, f, s = (len(spec.cursor_names), len(spec.field_paths()), len(spec.state_paths()))
    types = [storage_type(t) for t in spec.node_types()] + [i64] * 5 + [storage_type(t) for t in spec.state_types()] * 2 + [i32, i64]
    signature = [t.as_pointer(addrspace=1 if device else 0) for t in types] + [i64] * 5
    if has_reports(spec.updates):
        signature += [i64.as_pointer(addrspace=1 if device else 0), (i64 if spec.tagged_reports() else storage_type(spec.dtype)).as_pointer(addrspace=1 if device else 0), i64]
        if spec.tagged_reports():
            signature.append(i64.as_pointer(addrspace=1 if device else 0))
    if not device:
        signature.append(i64)
    fn = ir.Function(module, ir.FunctionType(ir.VoidType(), signature), name=f"jac_{spec.name}_cursors_{('batch' if device else 'lane')}")
    if device:
        fn.calling_convention = 'ptx_kernel'
    for arg, param in zip(fn.args, spec.metadata()['parameters']):
        arg.name = param['name']
    columns = fn.args[:f]
    tags, offsets, targets, heads, counts = fn.args[f:f + 5]
    initials = fn.args[f + 5:f + 5 + s]
    outputs = fn.args[f + 5 + s:f + 5 + 2 * s]
    status, queue = fn.args[f + 5 + 2 * s:f + 7 + 2 * s]
    n, e, m, capacity, max_rounds = fn.args[f + 7 + 2 * s:f + 12 + 2 * s]
    entry = fn.append_basic_block('entry')
    start = fn.append_basic_block('start')
    check = fn.append_basic_block('round.check')
    pop = fn.append_basic_block('round.pop')
    match = fn.append_basic_block('joint.match')
    body = fn.append_basic_block('ability')
    advance = fn.append_basic_block('advance')
    finish = fn.append_basic_block('finish')
    done = fn.append_basic_block('done')
    errors = {code: fn.append_basic_block(f'error.{code}') for code in range(1, 8)}
    b = ir.IRBuilder(entry)
    zero = ir.Constant(i64, 0)
    one = ir.Constant(i64, 1)
    lane = thread_index(module, b) if device else fn.args[-1]
    b.cbranch(b.icmp_unsigned('<', lane, m), start, done)
    b.position_at_end(start)
    state_slots = [b.alloca(value_type(t)) for t in spec.state_types()]
    for ptr, col, typ in zip(state_slots, initials, spec.state_types()):
        b.store(load_field(b, col, lane, typ), ptr)
    readers = [b.alloca(i64) for _ in range(k)]
    writers = [b.alloca(i64) for _ in range(k)]
    pending = [b.alloca(i64) for _ in range(k)]
    current = [b.alloca(i64) for _ in range(k)]
    steps = b.alloca(i64)
    b.store(zero, steps)
    reports = None
    if has_reports(spec.updates):
        base = f + 12 + 2 * s
        args = fn.args[base:base + 3]
        reports = ReportOutput(args[0], args[1], args[2], lane, m, errors[7], fn.args[base + 3] if spec.tagged_reports() else None)
        b.store(zero, b.gep(args[0], [lane]))
    for ch in range(k):
        index = b.add(b.mul(ir.Constant(i64, ch), m), lane)
        size = b.load(b.gep(counts, [index]))
        valid = fn.append_basic_block('seed.valid')
        b.cbranch(b.and_(b.icmp_unsigned('>', capacity, zero), b.icmp_unsigned('<=', size, capacity)), valid, errors[6])
        b.position_at_end(valid)
        b.store(zero, readers[ch])
        b.store(size, pending[ch])
        b.store(b.select(b.icmp_unsigned('==', size, capacity), zero, size), writers[ch])
        b.store(b.load(b.gep(heads, [index])), b.gep(queue, [b.add(b.mul(ir.Constant(i64, ch), b.mul(capacity, m)), lane)]))
    b.branch(check)
    b.position_at_end(check)
    alive = ir.Constant(ir.IntType(1), True)
    for ptr in pending:
        alive = b.and_(alive, b.icmp_unsigned('>', b.load(ptr), zero))
    b.cbranch(alive, pop, finish)
    b.position_at_end(pop)
    for ch in range(k):
        pos = b.load(readers[ch])
        qi = b.add(b.mul(b.add(b.mul(ir.Constant(i64, ch), capacity), pos), m), lane)
        nd = b.load(b.gep(queue, [qi]))
        valid = fn.append_basic_block('current.valid')
        b.cbranch(b.and_(b.icmp_signed('>=', nd, zero), b.icmp_unsigned('<', nd, n)), valid, errors[1])
        b.position_at_end(valid)
        b.store(nd, current[ch])
        nxt = b.add(pos, one)
        b.store(b.select(b.icmp_unsigned('==', nxt, capacity), zero, nxt), readers[ch])
        b.store(b.sub(b.load(pending[ch]), one), pending[ch])
    b.cbranch(b.icmp_unsigned('<', b.load(steps), max_rounds), match, errors[2])
    b.position_at_end(match)
    matches = ir.Constant(ir.IntType(1), True)
    for ptr in current:
        matches = b.and_(matches, b.icmp_signed('==', b.load(b.gep(tags, [b.load(ptr)])), one))
    b.cbranch(matches, body, advance)
    b.position_at_end(body)
    values = [load_field(b, col, b.load(ptr), typ) for ptr in current for col, typ in zip(columns, spec.node_types())]
    updated = lower_updates(spec.updates, b, [b.load(p) for p in state_slots], values, errors[3], errors[4], reports)
    for ptr, value in zip(state_slots, updated):
        b.store(value, ptr)
    for ch, edge in enumerate(spec.edges):
        if edge is None:
            continue
        enqueue = fn.append_basic_block('visit.begin')
        after = fn.append_basic_block('visit.end')
        if spec.guards[ch] is not None:
            b.cbranch(updated[spec.guards[ch]], enqueue, after)
        else:
            b.branch(enqueue)
        b.position_at_end(enqueue)
        row = b.add(b.mul(ir.Constant(i64, ch), b.add(n, one)), b.load(current[ch]))
        begin = b.load(b.gep(offsets, [row]))
        end = b.load(b.gep(offsets, [b.add(row, one)]))
        valid = fn.append_basic_block('row.valid')
        b.cbranch(b.and_(b.icmp_signed('>=', begin, zero), b.and_(b.icmp_unsigned('<=', begin, end), b.icmp_unsigned('<=', end, e))), valid, errors[5])
        b.position_at_end(valid)
        room = fn.append_basic_block('queue.room')
        degree = b.sub(end, begin)
        b.cbranch(b.icmp_unsigned('<=', degree, b.sub(capacity, b.load(pending[ch]))), room, errors[6])
        b.position_at_end(room)
        initial_tail = b.load(writers[ch])
        scan = fn.append_basic_block('edge.check')
        append = fn.append_basic_block('edge.append')
        store = fn.append_basic_block('edge.store')
        scanned = fn.append_basic_block('edges.end')
        b.branch(scan)
        b.position_at_end(scan)
        cursor = b.phi(i64)
        tail = b.phi(i64)
        cursor.add_incoming(begin, room)
        tail.add_incoming(initial_tail, room)
        b.cbranch(b.icmp_unsigned('<', cursor, end), append, scanned)
        b.position_at_end(append)
        target = b.load(b.gep(targets, [cursor]))
        b.cbranch(b.and_(b.icmp_signed('>=', target, zero), b.icmp_unsigned('<', target, n)), store, errors[1])
        b.position_at_end(store)
        qi = b.add(b.mul(b.add(b.mul(ir.Constant(i64, ch), capacity), tail), m), lane)
        b.store(target, b.gep(queue, [qi]))
        inc = b.add(tail, one)
        nxt = b.select(b.icmp_unsigned('==', inc, capacity), zero, inc)
        next_edge = b.add(cursor, one)
        b.branch(scan)
        cursor.add_incoming(next_edge, store)
        tail.add_incoming(nxt, store)
        b.position_at_end(scanned)
        b.store(tail, writers[ch])
        b.store(b.add(b.load(pending[ch]), degree), pending[ch])
        b.branch(after)
        b.position_at_end(after)
    b.branch(advance)
    b.position_at_end(advance)
    b.store(b.add(b.load(steps), one), steps)
    b.branch(check)
    b.position_at_end(finish)
    for ptr, col in zip(state_slots, outputs):
        store_field(b, b.load(ptr), col, lane)
    b.store(ir.Constant(i32, 0), b.gep(status, [lane]))
    b.branch(done)
    for code, block in errors.items():
        b.position_at_end(block)
        b.store(ir.Constant(i32, code), b.gep(status, [lane]))
        b.branch(done)
    b.position_at_end(done)
    b.ret_void()

def emit_cursor_artifact(specs, graph_format='csr'):
    from jaclang.compiler.backends.native.ptx import ptx_target, emit_ptx_artifact, PtxUnsupported
    if any((not isinstance(s, CursorSpec) for s in specs)):
        raise PtxUnsupported('Compile legacy and named-cursor kernels in separate artifacts')
    target = ptx_target()
    artifact = emit_ptx_artifact(build_cursor_module(specs, target), target, [s.metadata() for s in specs])
    artifact.format = 'jac-ptx-cursors-v1'
    artifact.argument_order = 'exact typed parameter order in each kernel; ordered per-cursor CSR for chain and CSR modes'
    return artifact

def make_schema(walker_class, module, source, digest, spec, graph_format):
    from jaclang.runtime.gpu import WalkerSchema
    funcs = walker_class._jac_entry_funcs_
    expected = {name: getattr(module, spec.node_type) for name in spec.cursor_names}
    if len(funcs) != 1 or walker_class._jac_exit_funcs_ or funcs[0].trigger != expected:
        raise ValueError('Loaded joint entry dispatch differs from compiled GPU schema')
    from pathlib import Path
    if Path(funcs[0].func.__code__.co_filename).resolve() != source:
        raise ValueError('Loaded ability does not belong to the current Jac source')
    artifact = emit_cursor_artifact([spec], graph_format)
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise RuntimeError('Source changed during GPU compilation')
    return WalkerSchema(walker_class, getattr(module, spec.node_type), getattr(module, spec.edge_type) if spec.edge_type else None, spec.state_field, spec.node_field, source, digest, funcs[0].func, artifact.ptx, artifact.kernels[0]['name'], spec.dtype, graph_format, spec.field_paths(), {p: getattr(module, n) for p, n in spec.node_objects.items()}, spec.state_paths(), {p: getattr(module, n) for p, n in spec.state_objects.items()}, bool(spec.report_parameters()), spec.node_types(), spec.state_types(), spec.tagged_reports(), spec)

@dataclass
class CursorBuffers:
    cursor_spec: CursorSpec
    node_columns: list[array]
    tags: array
    offsets: array
    targets: array
    heads: array
    seed_counts: array
    initial: array
    results: array
    status: array
    queue: array
    queue_capacity: int
    max_visits: int
    extra_initial: list[array]
    extra_results: list[array]
    reports: object = None
    prediction: dict = None
    timings: dict = None

    def columns(self):
        return self.node_columns

    def initial_columns(self):
        return [self.initial, *self.extra_initial]

    def result_columns(self):
        return [self.results, *self.extra_results]

    def arrays(self):
        return [*self.node_columns, self.tags, self.offsets, self.targets, self.heads, self.seed_counts, *self.initial_columns(), *self.result_columns(), self.status, self.queue]

    def arguments(self):
        return [len(self.tags), len(self.targets), len(self.status), self.queue_capacity, self.max_visits]

    def memory_plan(self):
        from jaclang.runtime.gpu_memory import GpuMemoryPlan, ArenaLayout
        offsets = []
        size = 0
        for buf in self.all_arrays():
            size = (size + 255) // 256 * 256
            offsets.append(size)
            size += len(buf) * buf.itemsize
        size = (size + 255) // 256 * 256
        payload = sum((len(buf) * buf.itemsize for buf in self.all_arrays()))

        class CursorMemoryPlan(GpuMemoryPlan):

            def payload_bytes(self):
                return payload
        plan = CursorMemoryPlan(len(self.tags), len(self.status), ArenaLayout(size, offsets, size), ArenaLayout(0, [], 0), graph_format='cursors', edge_count=len(self.targets), queue_capacity=self.queue_capacity, node_field_count=len(self.node_columns), state_field_count=len(self.initial_columns()))
        return plan

    def all_arrays(self):
        arrays = self.arrays()
        if self.reports:
            arrays += [self.reports.counts, self.reports.values]
            if self.reports.tags is not None:
                arrays.append(self.reports.tags)
        return arrays

def discovery_order(seeds, adjacency, budget):
    """Unique discovery order, NOT an event trajectory; never prunes actual rows."""
    if type(budget) is not int or budget < 0:
        raise ValueError('prediction_budget must be nonnegative')
    seen = set()
    order = []
    work = deque()
    expanded = 0
    for node in seeds:
        if node not in seen:
            seen.add(node)
            order.append(node)
            work.append(node)
    while work and expanded < budget:
        node = work.popleft()
        expanded += 1
        for target in adjacency[node]:
            if target not in seen:
                seen.add(target)
                order.append(target)
                work.append(target)
    return (order, dict(expanded=expanded, discovered=len(order), budget=budget, truncated=bool(work)))

def predict_layout(seed_rows, adjacency, node_count, budget=1000000):
    """Each channel is multi-source across the whole batch, lane order first.

    Merge channel candidates by discovery rank then declaration order; conflicts
    use the first occurrence. Remaining nodes keep discovery order on fallback.
    """
    candidates = []
    stats = []
    for seeds, rows in zip(seed_rows, adjacency):
        order, stat = discovery_order(seeds, rows, budget)
        candidates.append(order)
        stats.append(stat)
    merged = []
    seen = set()
    for rank in range(max(map(len, candidates), default=0)):
        for order in candidates:
            if rank < len(order) and order[rank] not in seen:
                seen.add(order[rank])
                merged.append(order[rank])
    merged.extend((i for i in range(node_count) if i not in seen))
    return (merged, dict(strategy='rank_then_cursor_first_occurrence', channels=stats, fallback='unpredicted nodes retain graph discovery order', candidate_orders=candidates))

def pack_cursors(schema, walkers, starts, queue_capacity=1024, max_visits=1000000, report_capacity=1024, *, layout='predicted', prediction_budget=1000000, random_seed=0, max_nodes=1000000, max_queue_bytes=512 * 1024 * 1024):
    from jaclang.runtime import gpu
    from jaclang.runtime.gpu_memory import check_csr_limits, typed_columns, report_buffers
    from jaclang.runtime.archetype import NodeArchetype, WalkerArchetype, NodeAnchor, anchor_key
    from jaclang.runtime.osp_kernel import scope_of
    from jaclang.runtime.graph_query import GraphQuery, QHop
    from jaclang.runtime.graph_walk import walk
    import sys
    begin = perf_counter()
    spec = schema.cursor_spec
    names = spec.cursor_names
    k = len(names)
    m = len(walkers)
    check_csr_limits(queue_capacity, max_visits)
    if layout not in ('current', 'predicted', 'random'):
        raise ValueError('Unknown cursor layout')
    if len(starts) != m or len({id(w) for w in walkers}) != m:
        raise ValueError('GPU starts need one binding per unique walker lane')
    if k * queue_capacity * m * 8 > max_queue_bytes:
        raise ValueError('GPU cursor queue storage exceeds configured host resource budget')
    if type(max_nodes) is not int or max_nodes < 1:
        raise ValueError('max_nodes must be positive')
    typed = []
    objects = []
    initial = [[] for _ in schema.state_paths()]
    owners = set()
    for w in walkers:
        if not isinstance(w, WalkerArchetype) or type(w) is not schema.walker_type:
            raise TypeError('GPU batch needs the exact compiled walker type')
        gpu.check_private(w.__jac__)
        if scope_of(w) is not None or w.__jac__.next or w.__jac__.ignores or w.__jac__.disengaged or w.__jac__.path:
            raise ValueError('GPU walker already has traversal state')
        objs = gpu.data_objects(w, schema.state_objects)
        for path in schema.state_objects:
            key = id(objs[path])
            if key in owners:
                raise ValueError('GPU walker nested state must be private')
            owners.add(key)
        for path, col, typ in zip(schema.state_paths(), initial, schema.state_types()):
            parent, field = gpu.field_parent(objs, path)
            col.append(gpu.scalar_value(getattr(parent, field), typ))
        typed.append(w)
        objects.append(objs)
    nodes = []
    slots = {}

    def slot(nd):
        if not isinstance(nd, NodeArchetype):
            raise TypeError('Cursor seeds and targets must be nodes')
        gpu.check_private(nd.__jac__)
        if getattr(type(nd), '_jac_entry_funcs_', ()) or getattr(type(nd), '_jac_exit_funcs_', ()):
            raise TypeError('GPU named cursors do not support node callbacks')
        key = anchor_key(nd.__jac__)
        if key not in slots:
            if len(nodes) >= max_nodes:
                raise ValueError('GPU graph exceeds max_nodes; graph packing is not truncated')
            slots[key] = len(nodes)
            nodes.append(nd)
        return slots[key]
    seeds = [[[] for _ in range(m)] for _ in names]
    for lane, binding in enumerate(starts):
        if not isinstance(binding, dict) or set(binding) != set(names):
            raise TypeError('Cursor start keys must exactly match declarations')
        for ch, name in enumerate(names):
            value = binding[name]
            values = [] if value is None else value if isinstance(value, list) else [value]
            if len(values) > queue_capacity:
                raise ValueError('Cursor initial queue exceeds queue_capacity')
            seeds[ch][lane] = [slot(nd) for nd in values]
    module = sys.modules[schema.walker_type.__module__]
    edges = [getattr(module, name) if name else None for name in spec.edges]
    adjacency = [[] for _ in names]
    idx = 0
    while idx < len(nodes):
        nd = nodes[idx]
        for ch, edge in enumerate(edges):
            row = []
            seen = set()
            if edge is not None:
                query = GraphQuery([nd], hops=[QHop(dir=2, edge=edge)], edges_only=True)
                pairs = walk([nd.__jac__], query, 1, False)
                if schema.graph_format == 'chain' and len(pairs) > 1:
                    raise ValueError('GPU chain channel requires at most one selected outgoing edge')
                for other, connection in pairs:
                    gpu.check_private(connection)
                    if type(connection.archetype) is not edge or connection.is_undirected:
                        raise ValueError('GPU requires exact directed edge types')
                    if not isinstance(other, NodeAnchor):
                        raise TypeError('GPU targets must be nodes')
                    target = slot(other.archetype)
                    if target not in seen:
                        seen.add(target)
                        row.append(target)
            adjacency[ch].append(row)
        idx += 1
    if schema.graph_format == 'chain':
        for rows in adjacency:
            gpu.check_finite_chains([row[0] if row else -1 for row in rows])
    collect_done = perf_counter()
    if type(prediction_budget) is not int or prediction_budget < 0:
        raise ValueError('prediction_budget must be nonnegative')
    prediction_started = perf_counter()
    if layout == 'predicted':
        seed_rows = [[nd for lane in channel for nd in lane] for channel in seeds]
        order, prediction = predict_layout(seed_rows, adjacency, len(nodes), prediction_budget)
    else:
        order = list(range(len(nodes)))
        prediction = dict(strategy='graph_discovery' if layout == 'current' else 'random_permutation',
                          channels=[], candidate_orders=[], budget=prediction_budget)
    predict_ms = (perf_counter() - prediction_started) * 1000 if layout == 'predicted' else 0.0
    reorder_started = perf_counter()
    if layout == 'random':
        random.Random(random_seed).shuffle(order)
    prediction['conditional_conservative'] = spec.conditional
    prediction['layout'] = layout
    prediction['order'] = order
    remap = {old: new for new, old in enumerate(order)}
    nodes = [nodes[i] for i in order]
    columns = [[] for _ in schema.field_paths()]
    tags = []
    node_owners = {}
    for idx, nd in enumerate(nodes):
        matches = isinstance(nd, schema.node_type)
        tags.append(int(matches))
        objs = gpu.data_objects(nd, schema.node_objects) if matches else {}
        for path in schema.node_objects if matches else ():
            key = id(objs[path])
            if key in owners or (key in node_owners and node_owners[key] != idx):
                raise ValueError('GPU node nested objects must have unique owners')
            node_owners[key] = idx
        for path, col, typ in zip(schema.field_paths(), columns, schema.node_types()):
            if matches:
                parent, field = gpu.field_parent(objs, path)
                col.append(gpu.scalar_value(getattr(parent, field), typ))
            else:
                col.append(0)
    offsets = []
    targets = []
    for rows in adjacency:
        offsets.append(len(targets))
        for old in order:
            targets.extend((remap[target] for target in rows[old]))
            offsets.append(len(targets))
    heads = []
    counts = []
    queue = array('q', [-1]) * (k * queue_capacity * m)
    for ch in range(k):
        for lane in range(m):
            row = seeds[ch][lane]
            heads.append(remap[row[0]] if row else -1)
            counts.append(len(row))
            for pos, target in enumerate(row):
                queue[(ch * queue_capacity + pos) * m + lane] = remap[target]
    initials = typed_columns(initial, schema.state_types(), schema.dtype)
    results = [array(col.typecode, [0]) * m for col in initials]
    buffers = CursorBuffers(spec, typed_columns(columns, schema.node_types(), schema.dtype), array('q', tags), array('q', offsets), array('q', targets), array('q', heads), array('q', counts), initials[0], results[0], array('I', [0]) * m, queue, queue_capacity, max_visits, initials[1:], results[1:], report_buffers(m, report_capacity, schema.dtype, schema.tagged_reports) if schema.emits_reports else None, prediction, dict(pack_ms=(perf_counter() - begin) * 1000,
             collect_ms=(collect_done - begin) * 1000, predict_ms=predict_ms,
             remap_soa_ms=(perf_counter() - reorder_started) * 1000))
    return gpu.PackedWalkerBatch(typed, nodes, buffers, objects)

def validate_buffers(buffers, session=None):
    from jaclang.runtime.gpu_memory import check_csr_limits, check_report_capacity, GpuScalarType
    spec = buffers.cursor_spec
    n, m, k = (len(buffers.tags), len(buffers.status), len(spec.cursor_names))
    check_csr_limits(buffers.queue_capacity, buffers.max_visits)
    expected = [(buffers.tags, n, 'q'), (buffers.offsets, k * (n + 1), 'q'), (buffers.targets, len(buffers.targets), 'q'), (buffers.heads, k * m, 'q'), (buffers.seed_counts, k * m, 'q'), (buffers.queue, k * buffers.queue_capacity * m, 'q'), (buffers.status, m, 'I')]
    for columns, types, length in ((buffers.columns(), spec.node_types(), n), (buffers.initial_columns(), spec.state_types(), m), (buffers.result_columns(), spec.state_types(), m)):
        if len(columns) != len(types):
            raise ValueError('Cursor buffer column count differs from compiled schema')
        for column, typ in zip(columns, types):
            expected.append((column, length, 'd' if typ == GpuScalarType.FLOAT64 else 'q'))
    if any((buf.typecode != code or len(buf) != length or buf.itemsize != (4 if code == 'I' else 8) for buf, length, code in expected)):
        raise ValueError('Cursor buffer shapes or scalar types differ from compiled schema')
    if session is not None:
        if session.kernel_name != f'jac_{spec.name}_cursors_batch' or session.node_field_count != len(spec.field_paths()) or session.state_field_count != len(spec.state_paths()):
            raise ValueError('Cursor buffers differ from the CUDA kernel schema')
        if session.node_dtypes and session.node_dtypes != spec.node_types() or (session.state_dtypes and session.state_dtypes != spec.state_types()):
            raise ValueError('Cursor CUDA field types differ from the schema')
        if session.emits_reports != bool(spec.report_parameters()) or session.tagged_reports != spec.tagged_reports():
            raise ValueError('Cursor CUDA report configuration differs from the schema')
    reports = buffers.reports
    if bool(spec.report_parameters()) != (reports is not None):
        raise ValueError('Cursor report buffers differ from schema')
    if reports is not None:
        check_report_capacity(reports.capacity, m)
        code = 'Q' if spec.tagged_reports() else 'd' if spec.dtype == GpuScalarType.FLOAT64 else 'q'
        if len(reports.counts) != m or reports.counts.typecode != 'Q' or len(reports.values) != m * reports.capacity or (reports.values.typecode != code):
            raise ValueError('Cursor report buffer shape or scalar type differs from schema')
        if spec.tagged_reports() != (reports.tags is not None) or (reports.tags is not None and (reports.tags.typecode != 'Q' or len(reports.tags) != len(reports.values))):
            raise ValueError('Cursor report tag buffers differ from schema')

def execute_cuda(session, buffers):
    """Explicit CUDA transfer/launch path; no host execution fallback."""
    session.check_thread()
    validate_buffers(buffers, session)
    d = session.driver
    plan = buffers.memory_plan()
    m = len(buffers.status)
    if not m:
        return plan
    grid = (m + session.block_size - 1) // session.block_size
    if grid > session.max_grid:
        raise ValueError('GPU batch exceeds grid limit')
    d.call('cuCtxPushCurrent_v2', session.context)
    failed = False
    try:
        started = perf_counter()
        session.graph_arena.reserve(d, plan.graph_layout.nbytes, plan.graph_layout.capacity)
        buffers.timings['allocate_ms'] = (perf_counter() - started) * 1000
        addresses = [session.graph_arena.address + off for off in plan.graph_layout.offsets]
        arrays = buffers.all_arrays()
        started = perf_counter()
        for addr, buf in zip(addresses, arrays):
            session.transfer('cuMemcpyHtoD_v2', addr, buf)
        buffers.timings['H2D_ms'] = (perf_counter() - started) * 1000
        base = len(buffers.arrays())
        args = addresses[:base] + buffers.arguments()
        if buffers.reports:
            args += [addresses[base], addresses[base + 1], buffers.reports.capacity]
            if buffers.reports.tags is not None:
                args.append(addresses[base + 2])
        holders = [c.c_uint64(v) for v in args]
        params = (c.c_void_p * len(holders))(*(c.addressof(v) for v in holders))
        started = perf_counter()
        d.call('cuLaunchKernel', session.function, grid, 1, 1, session.block_size, 1, 1, 0, None, params, None)
        d.call('cuCtxSynchronize')
        buffers.timings['kernel_sync_ms'] = (perf_counter() - started) * 1000
        started = perf_counter()
        outputs = {id(a) for a in [*buffers.result_columns(), buffers.status]}
        if buffers.reports:
            outputs.update((id(a) for a in arrays[base:]))
        for addr, buf in zip(addresses, arrays):
            if id(buf) in outputs:
                session.transfer('cuMemcpyDtoH_v2', addr, buf)
        buffers.timings['D2H_ms'] = (perf_counter() - started) * 1000
        plan.graph_layout.nbytes = max(plan.graph_layout.nbytes, session.graph_arena.nbytes)
        session.plan = plan
        return plan
    except BaseException:
        failed = True
        raise
    finally:
        popped = c.c_void_p()
        if failed:
            d.cleanup('cuCtxPopCurrent_v2', c.byref(popped))
            session.close()
        else:
            d.call('cuCtxPopCurrent_v2', c.byref(popped))

def run_jit(spec, buffers):
    """Test helper: execute precisely the device LLVM control flow on the host."""
    from jaclang.compiler.backends.native.llvm import binding as llvm
    validate_buffers(buffers)
    target = llvm.Target.from_default_triple().create_target_machine(opt=2)
    module = build_cursor_module([spec], target, False)
    engine = llvm.create_mcjit_compiler(module, target)
    engine.finalize_object()
    arrays = buffers.arrays()
    types = [c.c_double if buf.typecode == 'd' else c.c_uint32 if buf.typecode == 'I' else c.c_int64 for buf in arrays]
    argtypes = [c.POINTER(t) for t in types] + [c.c_uint64] * 5
    reports = buffers.reports
    if reports:
        argtypes += [c.POINTER(c.c_uint64), c.POINTER(c.c_uint64 if reports.tags is not None else c.c_double if reports.values.typecode == 'd' else c.c_int64), c.c_uint64]
        if reports.tags is not None:
            argtypes.append(c.POINTER(c.c_uint64))
    fn = c.CFUNCTYPE(None, *argtypes, c.c_uint64)(engine.get_function_address(f'jac_{spec.name}_cursors_lane'))
    ptrs = [c.cast(buf.buffer_info()[0], c.POINTER(t)) for buf, t in zip(arrays, types)]
    args = ptrs + buffers.arguments()
    if reports:
        args += [c.cast(reports.counts.buffer_info()[0], c.POINTER(c.c_uint64)), c.cast(reports.values.buffer_info()[0], argtypes[len(ptrs) + 6]), reports.capacity]
        if reports.tags is not None:
            args.append(c.cast(reports.tags.buffer_info()[0], c.POINTER(c.c_uint64)))
    started = perf_counter()
    for lane in reversed(range(len(buffers.status))):
        fn(*args, lane)
    for lane in (len(buffers.status), 2 ** 64 - 1):
        fn(*args, lane)
    buffers.timings['host_JIT_ms'] = (perf_counter() - started) * 1000
    return ([list(col) for col in buffers.result_columns()], list(buffers.status))
