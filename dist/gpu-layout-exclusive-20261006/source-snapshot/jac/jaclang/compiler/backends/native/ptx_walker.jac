import math;
import re;
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.types.types { ClassType }
import from jaclang.runtime.constants { EdgeDir }
import from jaclang.runtime.gpu_memory { GpuScalarType }
import from jaclang.compiler.backends.native.llvm { ir }
import jaclang.compiler.backends.native.llvm.binding as llvm;
import from jaclang.compiler.backends.native.ptx {
    PtxArtifact,
    PtxUnsupported,
    emit_ptx_artifact,
    ptx_target,
    thread_index
}

obj ChainExpr {
    has op: str,
        value: float | int | bool = 0.0,
        left: ChainExpr | None = None,
        right: ChainExpr | None = None,
        node_index: int = 0,
        state_index: int = 0,
        dtype: GpuScalarType | None = None;

    def lower(
        b: ir.IRBuilder,
        state: list[ir.Value],
        node_value: list[ir.Value],
        overflow: ir.Block,
        zero_divisor: ir.Block
    ) -> ir.Value {
        if self.op in ("state", "range_state") {
            return state[self.state_index];
        }
        if self.op == "node" {
            return node_value[self.node_index];
        }
        if self.op == "constant" {
            return ir.Constant(value_type(self.dtype) if self.dtype is not None else state[0].type, self.value);
        }
        assert self.left is not None;
        left = self.left.lower(b, state, node_value, overflow, zero_divisor);
        if self.op == "not" {
            return b.not_(left);
        }
        if self.op in ("and", "or") {
            rhs = b.function.append_basic_block("bool.right");
            merge = b.function.append_basic_block("bool.end");
            first = b.block;
            if self.op == "and" { b.cbranch(left, rhs, merge); }
            else { b.cbranch(left, merge, rhs); }
            b.position_at_end(rhs);
            assert self.right is not None;
            right = self.right.lower(b, state, node_value, overflow, zero_divisor);
            last = b.block;
            b.branch(merge);
            b.position_at_end(merge);
            result = b.phi(ir.IntType(1));
            result.add_incoming(left, first);
            result.add_incoming(right, last);
            return result;
        }
        integer = left.type == ir.IntType(64);
        if self.op == "neg" {
            return checked_int(b, "sub", ir.Constant(left.type, 0), left, overflow)
                if integer
                else b.fneg(left);
        }
        assert self.right is not None;
        right = self.right.lower(b, state, node_value, overflow, zero_divisor);
        if self.op == "range_next" {
            # Python range may terminate beyond int64. The private induction slot
            # saturates to stop rather than reporting overflow after the last item.
            step = self.right.value;
            threshold = (2 ** 63 - 1) - step if step > 0 else -(2 ** 63) - step;
            beyond = b.icmp_signed(">" if step > 0 else "<", left, ir.Constant(left.type, threshold));
            return b.select(beyond, state[self.node_index], b.add(left, right));
        }
        if self.op in ("==", "!=", "<", "<=", ">", ">=") {
            if left.type == ir.IntType(1) {
                return b.icmp_unsigned(self.op, left, right);
            }
            if integer {
                return b.icmp_signed(self.op, left, right);
            }
            return b.fcmp_unordered(self.op, left, right)
                if self.op == "!="
                else b.fcmp_ordered(self.op, left, right);
        }
        if integer {
            if self.op == "%" {
                nonzero = b.function.append_basic_block("mod.nonzero");
                zero = ir.Constant(left.type, 0);
                b.cbranch(b.icmp_signed("==", right, zero), zero_divisor, nonzero);
                b.position_at_end(nonzero);
                special = b.and_(
                    b.icmp_signed("==", left, ir.Constant(left.type, -(2 ** 63))),
                    b.icmp_signed("==", right, ir.Constant(left.type, -1))
                );
                divisor = b.select(special, ir.Constant(left.type, 1), right);
                remainder = b.srem(left, divisor);
                adjust = b.and_(
                    b.icmp_signed("!=", remainder, zero),
                    b.xor(
                        b.icmp_signed("<", remainder, zero),
                        b.icmp_signed("<", right, zero)
                    )
                );
                return b.select(adjust, b.add(remainder, right), remainder);
            }
            return checked_int(
                b, {"+": "add", "-": "sub", "*": "mul"}[self.op], left, right, overflow
            );
        }
        if self.op == "+" {
            return b.fadd(left, right);
        }
        if self.op == "-" {
            return b.fsub(left, right);
        }
        if self.op == "*" {
            return b.fmul(left, right);
        }
        raise PtxUnsupported(f"Unknown chain expression: {self.op}");
    }
}

obj StateUpdate {
    has expression: ChainExpr,
        target: int | None = None,
        taken: list[StateUpdate] = [],
        skipped: list[StateUpdate] = [],
        is_report: bool = False,
        is_loop: bool = False;

    def lower(
        b: ir.IRBuilder,
        state: list[ir.Value],
        node_value: list[ir.Value],
        overflow: ir.Block,
        zero_divisor: ir.Block,
        reports: ReportOutput | None = None
    ) -> list[ir.Value] {
        if self.is_loop {
            before = b.block;
            check = b.function.append_basic_block("loop.check");
            body = b.function.append_basic_block("loop.body");
            end = b.function.append_basic_block("loop.end");
            b.branch(check);
            b.position_at_end(check);
            carried = [b.phi(v.type, name="loop.state") for v in state];
            for (phi, value) in zip(carried, state) { phi.add_incoming(value, before); }
            condition = self.expression.lower(b, carried, node_value, overflow, zero_divisor);
            b.cbranch(condition, body, end);
            b.position_at_end(body);
            updated = lower_updates(self.taken, b, carried, node_value, overflow, zero_divisor, reports);
            back = b.block;
            b.branch(check);
            for (phi, value) in zip(carried, updated) { phi.add_incoming(value, back); }
            b.position_at_end(end);
            return carried;
        }
        value = self.expression.lower(b, state, node_value, overflow, zero_divisor);
        if self.is_report {
            assert reports is not None;
            reports.emit(b, value);
            return state;
        }
        if self.target is not None {
            result = state.copy();
            if self.target == len(result) { result.append(value); }
            else { result[self.target] = value; }
            return result;
        }
        yes_block = b.function.append_basic_block("update.then");
        no_block = b.function.append_basic_block("update.else");
        merge = b.function.append_basic_block("update.end");
        b.cbranch(value, yes_block, no_block);
        b.position_at_end(yes_block);
        yes = lower_updates(self.taken, b, state, node_value, overflow, zero_divisor, reports);
        yes_end = b.block;
        b.branch(merge);
        b.position_at_end(no_block);
        no = lower_updates(self.skipped, b, state, node_value, overflow, zero_divisor, reports);
        no_end = b.block;
        b.branch(merge);
        b.position_at_end(merge);
        merged: list[ir.Value] = [];
        for (left, right) in zip(yes, no) {
            phi = b.phi(left.type);
            phi.add_incoming(left, yes_end);
            phi.add_incoming(right, no_end);
            merged.append(phi);
        }
        return merged;
    }
}

def lower_updates(
    updates: list[StateUpdate],
    b: ir.IRBuilder,
    state: list[ir.Value],
    node_value: list[ir.Value],
    overflow: ir.Block,
    zero_divisor: ir.Block,
    reports: ReportOutput | None = None
) -> list[ir.Value] {
    result = state;
    for update in updates {
        result = update.lower(b, result, node_value, overflow, zero_divisor, reports);
    }
    return result;
}

obj ReportOutput {
    has counts: ir.Value,
        values: ir.Value,
        capacity: ir.Value,
        lane: ir.Value,
        walkers: ir.Value,
        full: ir.Block,
        tags: ir.Value | None = None;

    def emit(b: ir.IRBuilder, value: ir.Value) {
        address = b.gep(self.counts, [self.lane]);
        count = b.load(address);
        room = b.function.append_basic_block("report.room");
        b.cbranch(b.icmp_unsigned("<", count, self.capacity), room, self.full);
        b.position_at_end(room);
        slot = b.add(b.mul(count, self.walkers), self.lane);
        if self.tags is not None {
            tag = 2;
            if value.type == ir.IntType(1) {
                tag = 1;
                value = b.zext(value, ir.IntType(64));
            } elif value.type == ir.DoubleType() {
                tag = 3;
                value = b.bitcast(value, ir.IntType(64));
            }
            b.store(ir.Constant(ir.IntType(64), tag), b.gep(self.tags, [slot]));
        }
        b.store(value, b.gep(self.values, [slot]));
        b.store(b.add(count, ir.Constant(ir.IntType(64), 1)), address);
    }
}

def has_reports(updates: list[StateUpdate]) -> bool {
    return any(u.is_report or has_reports(u.taken) or has_reports(u.skipped) for u in updates);
}

def report_types(updates: list[StateUpdate]) -> list[GpuScalarType] {
    result: list[GpuScalarType] = [];
    for update in updates {
        if update.is_report {
            assert update.expression.dtype is not None;
            result.append(update.expression.dtype);
        }
        result.extend(report_types(update.taken));
        result.extend(report_types(update.skipped));
    }
    return result;
}

def value_type(dtype: GpuScalarType) -> ir.Type {
    if dtype == GpuScalarType.BOOL { return ir.IntType(1); }
    return ir.IntType(64) if dtype == GpuScalarType.INT64 else ir.DoubleType();
}

def storage_type(dtype: GpuScalarType) -> ir.Type {
    return ir.DoubleType() if dtype == GpuScalarType.FLOAT64 else ir.IntType(64);
}

def load_field(b: ir.IRBuilder, column: ir.Value, index: ir.Value, dtype: GpuScalarType) -> ir.Value {
    value = b.load(b.gep(column, [index]));
    return b.icmp_unsigned("!=", value, ir.Constant(ir.IntType(64), 0))
        if dtype == GpuScalarType.BOOL else value;
}

def store_field(b: ir.IRBuilder, value: ir.Value, column: ir.Value, index: ir.Value) {
    if value.type == ir.IntType(1) { value = b.zext(value, ir.IntType(64)); }
    b.store(value, b.gep(column, [index]));
}

def field_dtype(path: list[uni.HasVar]) -> GpuScalarType {
    typ = path[-1].type;
    assert isinstance(typ, ClassType);
    if typ.is_builtin("bool") { return GpuScalarType.BOOL; }
    return GpuScalarType.INT64 if typ.is_builtin("int") else GpuScalarType.FLOAT64;
}

def checked_int(
    b: ir.IRBuilder, operation: str, left: ir.Value, right: ir.Value, overflow: ir.Block
) -> ir.Value {
    name = f"llvm.s{operation}.with.overflow.i64";
    module = b.module;
    assert isinstance(module, ir.Module);
    fn = module.globals.get(name);
    if fn is None {
        fn = ir.Function(
            module,
            ir.FunctionType(
                ir.LiteralStructType([ir.IntType(64), ir.IntType(1)]),
                [ir.IntType(64)] * 2
            ),
            name
        );
    }
    assert isinstance(fn, ir.Function);
    pair = b.call(fn, [left, right]);
    result = b.extract_value(pair, 0);
    ok = b.function.append_basic_block("int.ok");
    b.cbranch(b.extract_value(pair, 1), overflow, ok);
    b.position_at_end(ok);
    return result;
}

obj ChainWalker {
    has name: str,
        node_type: str,
        edge_type: str,
        node_field: str,
        state_field: str,
        default_total: float | int | bool | None,
        updates: list[StateUpdate],
        dtype: GpuScalarType = GpuScalarType.FLOAT64,
        node_fields: list[str] = [],
        node_objects: dict[str, str] = {},
        state_fields: list[str] = [],
        state_objects: dict[str, str] = {},
        default_states: list[float | int | bool | None] = [],
        node_dtypes: list[GpuScalarType] = [],
        state_dtypes: list[GpuScalarType] = [];

    def node_types -> list[GpuScalarType] {
        return self.node_dtypes or [self.dtype for path in self.field_paths()];
    }

    def state_types -> list[GpuScalarType] {
        return self.state_dtypes or [self.dtype for path in self.state_paths()];
    }

    def tagged_reports -> bool {
        return any(typ != self.dtype or typ == GpuScalarType.BOOL for typ in report_types(self.updates));
    }

    def typed -> bool {
        return GpuScalarType.BOOL in [*self.node_types(), *self.state_types()]
            or self.tagged_reports();
    }

    def report_parameters -> list[dict[str, any]] {
        if not has_reports(self.updates) {
            return [];
        }
        result = [
            {"name": "report_counts", "dtype": "uint64", "length": "walker_count", "access": "write"},
            {"name": "report_values", "dtype": "uint64" if self.tagged_reports() else self.dtype.value, "length": "report_capacity * walker_count", "access": "write"},
            {"name": "report_capacity", "dtype": "uint64"}
        ];
        if self.tagged_reports() {
            result.append({"name": "report_tags", "dtype": "uint64", "length": "report_capacity * walker_count", "access": "write"});
        }
        return result;
    }

    def field_paths -> list[str] {
        return self.node_fields or [self.node_field];
    }

    def state_paths -> list[str] {
        return self.state_fields or [self.state_field];
    }

    def state_parameters(output: bool = False) -> list[dict[str, any]] {
        prefix = "results" if output else "initial";
        return [
            {
                "name": ("results" if output else "initial_total")
                    if i == 0
                    else f"{prefix}_{i}",
                "dtype": self.state_types()[i].value,
                "length": "walker_count",
                "access": "write" if output else "read",
                "field_path": path
            } for (i, path) in enumerate(self.state_paths())
        ];
    }

    def field_parameters -> list[dict[str, any]] {
        return [
            {
                "name": "values" if i == 0 else f"values_{i}",
                "dtype": self.node_types()[i].value,
                "length": "node_count",
                "access": "read",
                "field_path": path
            } for (i, path) in enumerate(self.field_paths())
        ];
    }

    def metadata -> dict[str, any] {
        return {
            "name": f"jac_{self.name}_batch",
            "kind": "chain_walker",
            "walker_type": self.name,
            "node_type": self.node_type,
            "edge_type": self.edge_type,
            "node_field": self.node_field,
            "node_fields": self.field_paths(),
            "node_objects": self.node_objects,
            "state_field": self.state_field,
            "state_fields": self.state_paths(),
            "state_objects": self.state_objects,
            "default_initial_states": self.default_states or [self.default_total],
            "default_initial_state": self.default_total,
            "scalar_dtype": self.dtype.value,
            "node_dtypes": [t.value for t in self.node_types()],
            "state_dtypes": [t.value for t in self.state_types()],
            "parameters": self.field_parameters()
                + [
                    {
                        "name": "next",
                        "dtype": "int64",
                        "length": "node_count",
                        "access": "read"
                    },
                    {
                        "name": "heads",
                        "dtype": "int64",
                        "length": "walker_count",
                        "access": "read"
                    },

                ]
                + self.state_parameters()
                + self.state_parameters(True)
                + [
                    {
                        "name": "status",
                        "dtype": "uint32",
                        "length": "walker_count",
                        "access": "write"
                    },
                    {"name": "node_count", "dtype": "uint64"},
                    {"name": "walker_count", "dtype": "uint64"}
                ] + self.report_parameters(),
            "reports": {"dtype": "tagged" if self.tagged_reports() else self.dtype.value, "tags": {"1": "bool", "2": "int64", "3": "float64"} if self.tagged_reports() else {}, "layout": "report_values[slot * walker_count + lane]"} if has_reports(self.updates) else None,
            "null_node": -1,
            "status_codes": {
                "0": "success",
                "1": "invalid_node_index",
                "2": "cycle",
                "3": "integer_overflow",
                "4": "integer_modulo_by_zero",
                "7": "report_capacity_exceeded"
            },
            "results_on_error": "unchanged; ignore results when status is nonzero",
            "graph_contract": "finite chains of the declared node/edge types; at most one outgoing edge per node",
            "concurrency": "independent walkers; shared read-only graph; disjoint output buffers",
            "layout": "SoA; arbitrary node order with remapped next and heads"
        };
    }
}

def reject(nd: uni.UniNode, reason: str) {
    raise PtxUnsupported(
        f"{nd.loc.mod_path}:{nd.loc.first_line}:{nd.loc.col_start}: {reason}"
    );
}

def plain_archetype(arch: uni.Archetype) {
    if arch.base_classes
        or arch.decorators
        or arch.type_params
        or arch.keywords
        or arch.src_endpoint is not None
        or arch.tgt_endpoint is not None {
        reject(
            arch,
            "GPU chains require plain local archetypes without inheritance or decorators"
        );
    }
    if any(isinstance(k, uni.Token) and k.value == "async" for k in arch.kid) {
        reject(arch, "Async archetypes are not supported by GPU chains");
    }
}

def ordinary_field(field: uni.HasVar) {
    owner = field.parent;
    if not isinstance(owner, uni.ArchHas)
        or owner.is_static
        or owner.is_frozen
        or field.defer
        or field.accessors {
        reject(field, "GPU fields require ordinary instance fields without accessors");
    }
}

obj FieldProjection {
    has fields: list[list[uni.HasVar]] = [],
        objects: dict[str, str] = {},
        dtype: GpuScalarType | None = None;
}

def project_fields(
    nd: uni.Archetype,
    archs: dict[str, uni.Archetype],
    dtype: GpuScalarType | None = None
) -> FieldProjection {
    result = FieldProjection(dtype=dtype);
    def expand(arch: uni.Archetype, path: list[uni.HasVar], ancestors: set[str]) {
        if arch.name.value in ancestors {
            reject(arch, "Recursive GPU field types cannot be flattened");
        }
        plain_archetype(arch);
        if arch.arch_kind != "walker"
            and any(not isinstance(s, uni.ArchHas) for s in arch.body) {
            reject(
                arch,
                "GPU node data and nested objects cannot have abilities or behavior"
            );
        }
        fields = arch.get_has_vars();
        if not fields {
            reject(arch, "GPU data requires at least one numeric or boolean leaf field");
        }
        for field in fields {
            ordinary_field(field);
            typ = field.type;
            if field.type_tag is None or not isinstance(typ, ClassType) {
                reject(
                    field,
                    "GPU node fields require fixed checked numeric, boolean or object types"
                );
            }
            assert isinstance(typ, ClassType);
            nested_path = [*path, field];
            if typ.is_builtin("int") or typ.is_builtin("float") or typ.is_builtin("bool") {
                if not typ.is_builtin("bool") and result.dtype in (None, GpuScalarType.BOOL) {
                    result.dtype = GpuScalarType.INT64
                        if typ.is_builtin("int")
                        else GpuScalarType.FLOAT64;
                }
                if not typ.is_builtin("bool") and typ.is_builtin("int") != (result.dtype == GpuScalarType.INT64) {
                    reject(
                        field,
                        "GPU node leaves and walker state must have the same numeric type"
                    );
                }
                result.fields.append(nested_path);
            } else {
                nested = archs.get(typ.shared.class_name);
                if nested is None
                    or nested.arch_type.value != "obj"
                    or typ.get_class_symbol() is not nested.name.sym {
                    reject(
                        field,
                        "GPU nested fields require plain local objects with fixed numeric or boolean leaves"
                    );
                }
                assert nested is not None;
                result.objects[".".join(f.name.value for f in nested_path)] = nested.name.value;
                expand(nested, nested_path, ancestors | {arch.name.value});
            }
        }
    }
    expand(nd, [], set());
    if result.dtype is None { result.dtype = GpuScalarType.BOOL; }
    return result;
}

def field_path_ref(expr: uni.Expr, path: list[uni.HasVar], receiver: str) -> bool {
    current = expr;
    for field in reversed(path) {
        if not isinstance(current, uni.AtomTrailer)
            or not current.is_attr
            or current.is_null_ok
            or current.is_genai
            or not isinstance(current.right, uni.Name)
            or current.right.sym is None
            or current.right.sym is not field.name.sym {
            return False;
        }
        assert isinstance(current, uni.AtomTrailer);
        current = current.target;
    }
    if receiver.startswith("here:") {
        return isinstance(current, uni.AtomTrailer) and current.cursor_name == receiver.split(":", 1)[1];
    }
    return isinstance(current, uni.SpecialVarRef) and current.value == receiver;
}

def numeric_literal(expr: uni.Expr, dtype: GpuScalarType) -> float | int | bool | None {
    if dtype == GpuScalarType.BOOL and isinstance(expr, uni.Bool) { return expr.lit_value; }
    value = expr;
    sign = 1;
    if isinstance(value, uni.UnaryExpr) and value.op.value in ("+", "-") {
        sign = -1 if value.op.value == "-" else 1;
        value = value.operand;
    }
    if dtype == GpuScalarType.INT64 and isinstance(value, uni.Int) {
        result = sign * value.lit_value;
        if not -(2 ** 63) <= result < 2 ** 63 {
            reject(expr, "GPU integer literals must fit signed int64");
        }
        return result;
    }
    if dtype == GpuScalarType.FLOAT64 and isinstance(value, uni.Float) {
        return sign * value.lit_value;
    }
    return None;
}

def chain_expr(
    expr: uni.Expr,
    state: list[list[uni.HasVar]],
    nd: list[list[uni.HasVar]],
    dtype: GpuScalarType,
    locals: dict[str, ChainExpr]
) -> ChainExpr {
    if isinstance(expr, uni.Name) and expr.value in locals {
        return locals[expr.value];
    }
    if isinstance(expr, uni.CfgExpr) {
        return chain_expr(expr.expr, state, nd, dtype, locals);
    }
    if isinstance(expr, uni.AtomUnit) and isinstance(expr.value, uni.Expr) {
        return chain_expr(expr.value, state, nd, dtype, locals);
    }
    if isinstance(expr, uni.Bool) {
        return ChainExpr("constant", value=expr.lit_value, dtype=GpuScalarType.BOOL);
    }
    literal_node = expr.operand if isinstance(expr, uni.UnaryExpr) and expr.op.value in ("+", "-") else expr;
    literal_type = GpuScalarType.INT64 if isinstance(literal_node, uni.Int) else GpuScalarType.FLOAT64 if isinstance(literal_node, uni.Float) else dtype;
    literal = numeric_literal(expr, literal_type);
    if literal is not None {
        return ChainExpr("constant", value=literal, dtype=literal_type);
    }
    for (i, path) in enumerate(state) {
        if field_path_ref(expr, path, "self") {
            return ChainExpr("state", state_index=i, dtype=field_dtype(path));
        }
    }
    for (i, path) in enumerate(nd) {
        if field_path_ref(expr, path, "here:" + getattr(nd, "cursor_names")[i] if hasattr(nd, "cursor_names") else "here") {
            return ChainExpr("node", node_index=i, dtype=field_dtype(path));
        }
    }
    if isinstance(expr, uni.BoolExpr) {
        items = [chain_expr(v, state, nd, dtype, locals) for v in expr.values];
        if any(v.dtype != GpuScalarType.BOOL for v in items) {
            reject(expr, "GPU logical operators require boolean operands");
        }
        result = items[0];
        for item in items[1:] {
            result = ChainExpr(expr.op.value, left=result, right=item, dtype=GpuScalarType.BOOL);
        }
        return result;
    }
    if isinstance(expr, uni.UnaryExpr) and expr.op.value in ("+", "-", "not") {
        operand = chain_expr(expr.operand, state, nd, dtype, locals);
        if expr.op.value == "not" {
            if operand.dtype != GpuScalarType.BOOL { reject(expr, "GPU not requires a boolean operand"); }
            return ChainExpr("not", left=operand, dtype=GpuScalarType.BOOL);
        }
        if operand.dtype == GpuScalarType.BOOL { reject(expr, "GPU arithmetic requires numeric operands"); }
        return operand if expr.op.value == "+" else ChainExpr("neg", left=operand, dtype=operand.dtype);
    }
    if isinstance(expr, uni.CompareExpr) and len(expr.ops) == 1 and len(expr.rights) == 1 {
        left = chain_expr(expr.left, state, nd, dtype, locals);
        right = chain_expr(expr.rights[0], state, nd, dtype, locals);
        if left.dtype != right.dtype { reject(expr, "GPU comparisons require matching operand types"); }
        if expr.ops[0].value not in ("==", "!=", "<", "<=", ">", ">=") {
            reject(expr, "Unsupported GPU comparison");
        }
        return ChainExpr(expr.ops[0].value, left=left, right=right, dtype=GpuScalarType.BOOL);
    }
    if isinstance(expr, uni.BinaryExpr) and isinstance(expr.op, uni.Token)
        and expr.op.value in ("+", "-", "*", "%") {
        left = chain_expr(expr.left, state, nd, dtype, locals);
        right = chain_expr(expr.right, state, nd, dtype, locals);
        if left.dtype != right.dtype or left.dtype == GpuScalarType.BOOL
            or (expr.op.value == "%" and left.dtype != GpuScalarType.INT64) {
            reject(expr, "GPU arithmetic requires matching numeric operand types");
        }
        return ChainExpr(expr.op.value, left=left, right=right, dtype=left.dtype);
    }
    reject(expr, "Unsupported GPU expression; expected typed fields, literals, arithmetic or boolean operators");
    raise AssertionError("unreachable");
}

def literal_default(field: uni.HasVar, dtype: GpuScalarType) -> float | int | bool {
    value = numeric_literal(field.value, dtype)
        if isinstance(field.value, uni.Expr)
        else None;
    if value is None or not math.isfinite(value) {
        reject(
            field, "GPU walker state requires a finite matching numeric literal default"
        );
    }
    assert value is not None;
    return value;
}

def chain_condition(
    expr: uni.Expr,
    state: list[list[uni.HasVar]],
    nd: list[list[uni.HasVar]],
    dtype: GpuScalarType,
    locals: dict[str, ChainExpr]
) -> ChainExpr {
    result = chain_expr(expr, state, nd, dtype, locals);
    if result.dtype != GpuScalarType.BOOL { reject(expr, "GPU conditions require a boolean expression"); }
    return result;
}

def chain_update(
    stmt: uni.UniNode,
    state: list[list[uni.HasVar]],
    nd: list[list[uni.HasVar]],
    dtype: GpuScalarType,
    locals: dict[str, ChainExpr],
    allow_new: bool = True
) -> StateUpdate {
    if isinstance(stmt, (uni.WhileStmt, uni.InForStmt)) {
        if stmt.else_body is not None { reject(stmt, "GPU loop-else is unsupported"); }
        if isinstance(stmt, uni.WhileStmt) {
            condition = chain_condition(stmt.condition, state, nd, dtype, locals);
            return StateUpdate(condition,
                taken=[chain_update(s, state, nd, dtype, locals, False) for s in stmt.body], is_loop=True);
        }
        assert isinstance(stmt, uni.InForStmt);
        call = stmt.collection;
        if stmt.is_async or stmt.is_comptime or not isinstance(stmt.target, uni.Name)
            or not isinstance(call, uni.FuncCall) or not isinstance(call.target, uni.Name)
            or call.target.value != "range" or "range" in locals or call.params is None
            or not 1 <= len(call.params) <= 3 {
            reject(stmt, "GPU for requires a scalar target and builtin range with 1-3 positional arguments");
        }
        assert isinstance(call, uni.FuncCall) and call.params is not None;
        if not isinstance(call.target.type, ClassType) or not call.target.type.is_builtin("range") {
            reject(stmt, "GPU for requires the builtin range, not a shadowed callable");
        }
        args: list[ChainExpr] = [];
        for arg in call.params {
            if not isinstance(arg, uni.Expr) { reject(stmt, "GPU range requires positional arguments"); }
            value = chain_expr(arg, state, nd, dtype, locals);
            if value.dtype != GpuScalarType.INT64 { reject(stmt, "GPU range bounds require int64"); }
            args.append(value);
        }
        step = 1;
        if len(call.params) == 3 {
            literal = numeric_literal(call.params[2], GpuScalarType.INT64);
            if not isinstance(literal, int) or literal == 0 {
                reject(stmt, "GPU range step requires a nonzero integer literal");
            }
            step = literal;
        }
        assert isinstance(stmt.target, uni.Name);
        name = stmt.target.value;
        if name in locals { reject(stmt, "GPU range target must be a fresh local name"); }
        index = len(state) + len(locals);
        counter = ChainExpr("range_state", state_index=index, dtype=GpuScalarType.INT64);
        locals[name] = counter;
        stop = ChainExpr("state", state_index=index + 1, dtype=GpuScalarType.INT64);
        locals[f"$range{index}"] = stop;
        start = args[0] if len(args) > 1 else ChainExpr("constant", value=0, dtype=GpuScalarType.INT64);
        bound = args[1] if len(args) > 1 else args[0];
        body = [chain_update(s, state, nd, dtype, locals, False) for s in stmt.body];
        del locals[name];
        locals[f"$counter{index}"] = counter;
        body.append(StateUpdate(ChainExpr("range_next", left=counter,
            right=ChainExpr("constant", value=step, dtype=GpuScalarType.INT64),
            dtype=GpuScalarType.INT64, node_index=index + 1), target=index));
        loop = StateUpdate(ChainExpr("<" if step > 0 else ">", left=counter, right=stop,
            dtype=GpuScalarType.BOOL), taken=body, is_loop=True);
        return StateUpdate(ChainExpr("constant", value=True, dtype=GpuScalarType.BOOL),
            taken=[StateUpdate(start, target=index), StateUpdate(bound, target=index + 1), loop]);
    }
    if isinstance(stmt, uni.ReportStmt) {
        return StateUpdate(chain_expr(stmt.expr, state, nd, dtype, locals), is_report=True);
    }
    if isinstance(stmt, uni.IfStmt) and not stmt.is_comptime {
        otherwise: list[StateUpdate] = [];
        tail = stmt.else_body;
        if isinstance(tail, uni.ElseIf) {
            otherwise = [chain_update(tail, state, nd, dtype, locals, False)];
        } elif isinstance(tail, uni.ElseStmt) {
            otherwise = [chain_update(s, state, nd, dtype, locals, False) for s in tail.body];
        }
        return StateUpdate(
            chain_condition(stmt.condition, state, nd, dtype, locals),
            taken=[chain_update(s, state, nd, dtype, locals, False) for s in stmt.body],
            skipped=otherwise
        );
    }
    if not isinstance(stmt, uni.Assignment)
        or len(stmt.target) != 1
        or not isinstance(stmt.value, uni.Expr) {
        reject(
            stmt, "GPU bodies support scalar assignments, reports, if/elif/else, while and for/range; visit, break and continue inside loops are unsupported"
        );
    }
    assert isinstance(stmt, uni.Assignment) and isinstance(stmt.value, uni.Expr);
    target = next(
        (
            i
            for (i, path) in enumerate(state)
            if field_path_ref(stmt.target[0], path, "self")
        ),
        -1
    );
    expression = chain_expr(stmt.value, state, nd, dtype, locals);
    if target < 0 {
        if not isinstance(stmt.target[0], uni.Name) { reject(stmt, "GPU assignment requires a private field or scalar local"); }
        name = stmt.target[0].value;
        symbol = stmt.target[0].sym;
        if symbol is None or not isinstance(symbol.parent_tab, (uni.Ability, uni.InForStmt)) {
            reject(stmt, "GPU scalar locals must belong to the entry ability, not module state");
        }
        if name not in locals {
            if not allow_new { reject(stmt, "GPU locals must be initialized at ability top level before branches or loops"); }
            if stmt.aug_op is not None { reject(stmt, "GPU local must be initialized before use"); }
            locals[name] = ChainExpr("state", state_index=len(state) + len(locals), dtype=expression.dtype);
        }
        if locals[name].op == "range_state" { reject(stmt, "GPU range induction variables are read-only"); }
        target = locals[name].state_index;
        target_type = locals[name].dtype;
    } else { target_type = field_dtype(state[target]); }
    if expression.dtype != target_type { reject(stmt, "GPU assignment requires the field's declared type"); }
    if stmt.aug_op is not None {
        if target_type == GpuScalarType.BOOL { reject(stmt, "GPU boolean fields do not support arithmetic assignments"); }
        op = stmt.aug_op.value;
        if op not in ("+=", "-=", "*=")
            and not (op == "%=" and target_type == GpuScalarType.INT64) {
            reject(stmt, "Unsupported GPU chain assignment");
        }
        expression = ChainExpr(
            op[0], left=ChainExpr("state", state_index=target, dtype=target_type), right=expression, dtype=target_type
        );
    }
    return StateUpdate(expression, target=target);
}

def select_chain_walkers(module: uni.Module, names: list[str]) -> list[ChainWalker] {
    if not names or len(set(names)) != len(names) {
        raise PtxUnsupported("Select at least one --gpu-entry, without duplicates");
    }
    archs = {
        a.name.value: a
        for a in module.body
        if isinstance(a, uni.Archetype)
    };
    result: list[ChainWalker] = [];
    for name in names {
        arch = archs.get(name);
        if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", name)
            or arch is None
            or arch.arch_kind != "walker" {
            raise PtxUnsupported(f"Local walker not found: {name}");
        }
        assert arch is not None;
        if any(isinstance(s, uni.CursorDecl) for s in arch.body) {
            import from jaclang.runtime.gpu_cursors { select_cursor_walker }
            result.append(select_cursor_walker(module, arch));
            continue;
        }
        plain_archetype(arch);
        states = project_fields(arch, archs);
        dtype = states.dtype;
        assert dtype is not None;
        state_paths = [".".join(f.name.value for f in path) for path in states.fields];
        defaults = [
            literal_default(path[0], field_dtype(path)) if len(path) == 1 else None
            for path in states.fields
        ];
        abilities = arch.get_methods();
        if len(abilities) != 1
            or any(not isinstance(s, (uni.ArchHas, uni.Ability)) for s in arch.body) {
            reject(
                arch,
                "GPU chains require exactly one entry ability and no other walker behavior"
            );
        }
        ability = abilities[0];
        signature = ability.signature;
        if not isinstance(signature, uni.EventSignature)
            or signature.event.value != "entry"
            or ability.is_async
            or ability.is_static
            or ability.is_classmethod
            or ability.is_override
            or ability.is_abstract
            or ability.decorators
            or ability.type_params {
            reject(ability, "GPU chains require a plain synchronous entry ability");
        }
        assert isinstance(signature, uni.EventSignature);
        trigger = signature.arch_tag_info;
        nd = archs.get(trigger.value) if isinstance(trigger, uni.Name) else None;
        if nd is None
            or nd.arch_kind != "node"
            or not isinstance(trigger, uni.Name)
            or trigger.sym is not nd.name.sym {
            reject(signature, "GPU chains require one explicit local node trigger");
        }
        assert nd is not None;
        plain_archetype(nd);
        projection = project_fields(nd, archs, dtype);
        if dtype == GpuScalarType.BOOL { dtype = projection.dtype; }
        assert dtype is not None;
        paths = [".".join(f.name.value for f in path) for path in projection.fields];
        body = ability.body;
        if not isinstance(body, list)
            or len(body) < 2
            or not isinstance(body[-1], uni.VisitStmt) {
            reject(
                ability, "GPU body requires state updates followed by one tail visit"
            );
        }
        visit_stmt = body[-1];
        assert isinstance(visit_stmt, uni.VisitStmt);
        locals: dict[str, ChainExpr] = {};
        updates = [
            chain_update(stmt, states.fields, projection.fields, dtype, locals)
            for stmt in body[:-1]
        ];
        # Seed private SSA slots on each node entry, without changing the public ABI.
        updates = [StateUpdate(ChainExpr("constant", value=0, dtype=value.dtype),
            target=value.state_index) for value in sorted(locals.values(), key=lambda (v: ChainExpr) { v.state_index; })] + updates;
        query = visit_stmt.target;
        if visit_stmt.else_body is not None
            or visit_stmt.insert_loc is not None
            or not isinstance(query, uni.EdgeRefTrailer)
            or query.edges_only
            or query.is_async
            or len(query.chain) != 1
            or not isinstance(query.chain[0], uni.EdgeOpRef) {
            reject(
                visit_stmt, "GPU chains require a single outgoing typed-edge tail visit"
            );
        }
        assert isinstance(query, uni.EdgeRefTrailer);
        hop = query.chain[0];
        assert isinstance(hop, uni.EdgeOpRef);
        filt = hop.filter_cond;
        if hop.edge_dir != EdgeDir.OUT
            or filt is None
            or filt.compares
            or not isinstance(filt.f_type, uni.Name) {
            reject(hop, "GPU chains require an outgoing edge type without filters");
        }
        assert filt is not None and isinstance(filt.f_type, uni.Name);
        edge_arch = archs.get(filt.f_type.value);
        if edge_arch is None
            or edge_arch.arch_kind != "edge"
            or filt.f_type.sym is not edge_arch.name.sym {
            reject(hop, "GPU chains require a local edge type");
        }
        assert edge_arch is not None;
        plain_archetype(edge_arch);
        if edge_arch.body {
            reject(
                edge_arch, "GPU chains require an edge type without fields or behavior"
            );
        }
        result.append(
            ChainWalker(
                name,
                nd.name.value,
                edge_arch.name.value,
                paths[0],
                state_paths[0],
                defaults[0],
                updates,
                dtype,
                paths,
                projection.objects,
                state_paths,
                states.objects,
                defaults,
                [field_dtype(path) for path in projection.fields],
                [field_dtype(path) for path in states.fields]
            )
        );
    }
    return result;
}

def build_chain_module(
    walkers: list[ChainWalker], target: llvm.TargetMachine, device: bool = True
) -> llvm.ModuleRef {
    module = ir.Module(name="jac_gpu_chain_walkers");
    module.triple = target.triple;
    module.data_layout = str(target.target_data);
    for spec in walkers {
        lower_chain(module, spec, device);
    }
    compiled = llvm.parse_assembly(str(module));
    compiled.verify();
    return compiled;
}

def lower_chain(module: ir.Module, spec: ChainWalker, device: bool) {
    (i32, i64, f64) = (ir.IntType(32), ir.IntType(64), ir.DoubleType());
    scalar = storage_type(spec.dtype);
    space = 1 if device else 0;
    field_count = len(spec.field_paths());
    state_count = len(spec.state_paths());
    signature = [
        t.as_pointer(addrspace=space)
        for t in [storage_type(t) for t in spec.node_types()]
            + [i64, i64]
            + [storage_type(t) for t in spec.state_types()] * 2
            + [i32]
    ]
        + [i64, i64];
    if has_reports(spec.updates) {
        signature += [i64.as_pointer(addrspace=space), (i64 if spec.tagged_reports() else scalar).as_pointer(addrspace=space), i64];
        if spec.tagged_reports() { signature.append(i64.as_pointer(addrspace=space)); }
    }
    if not device {
        signature.append(i64);
    }
    suffix = "batch" if device else "lane";
    fn = ir.Function(
        module,
        ir.FunctionType(ir.VoidType(), signature),
        name=f"jac_{spec.name}_{suffix}"
    );
    if device {
        fn.calling_convention = "ptx_kernel";
    }
    for (arg, name) in zip(
        fn.args, [p["name"] for p in spec.metadata()["parameters"]] + ["index"]
    ) {
        arg.name = name;
    }
    values = fn.args[:field_count];
    (links, heads) = fn.args[field_count:field_count + 2];
    initial = fn.args[field_count + 2:field_count + 2 + state_count];
    output = fn.args[field_count + 2 + state_count:field_count + 2 + 2 * state_count];
    (status, node_count, count) = fn.args[field_count + 2 + 2 * state_count:field_count
        + 5
        + 2 * state_count];
    entry_bb = fn.append_basic_block("entry");
    start = fn.append_basic_block("start");
    check = fn.append_basic_block("chain.check");
    bounds = fn.append_basic_block("node.bounds");
    limit = fn.append_basic_block("cycle.check");
    body = fn.append_basic_block("ability");
    finish = fn.append_basic_block("finish");
    bad_index = fn.append_basic_block("invalid.node");
    cycle = fn.append_basic_block("cycle");
    overflow = fn.append_basic_block("integer.overflow");
    zero_divisor = fn.append_basic_block("integer.modulo.zero");
    done = fn.append_basic_block("done");
    b = ir.IRBuilder(entry_bb);
    index = thread_index(module, b) if device else fn.args[-1];
    b.cbranch(b.icmp_unsigned("<", index, count), start, done);
    b.position_at_end(start);
    reports: ReportOutput | None = None;
    report_full = fn.append_basic_block("report.capacity.exceeded");
    if has_reports(spec.updates) {
        args = fn.args[field_count + 5 + 2 * state_count:field_count + 8 + 2 * state_count];
        reports = ReportOutput(args[0], args[1], args[2], index, count, report_full,
            fn.args[field_count + 8 + 2 * state_count] if spec.tagged_reports() else None);
        b.store(ir.Constant(i64, 0), b.gep(args[0], [index]));
    }
    head = b.load(b.gep(heads, [index]));
    seeds = [load_field(b, column, index, typ) for (column, typ) in zip(initial, spec.state_types())];
    b.branch(check);
    b.position_at_end(check);
    current = b.phi(i64, name="current");
    state = [b.phi(value_type(typ), name=path) for (path, typ) in zip(spec.state_paths(), spec.state_types())];
    steps = b.phi(i64, name="steps");
    current.add_incoming(head, start);
    for (phi, seed) in zip(state, seeds) {
        phi.add_incoming(seed, start);
    }
    steps.add_incoming(ir.Constant(i64, 0), start);
    b.cbranch(b.icmp_signed("==", current, ir.Constant(i64, -1)), finish, bounds);
    b.position_at_end(bounds);
    valid = b.and_(
        b.icmp_signed(">=", current, ir.Constant(i64, 0)),
        b.icmp_unsigned("<", current, node_count)
    );
    b.cbranch(valid, limit, bad_index);
    b.position_at_end(limit);
    b.cbranch(b.icmp_unsigned("<", steps, node_count), body, cycle);
    b.position_at_end(body);
    node_value = [
        load_field(b, column, current, typ)
        for (column, typ) in zip(values, spec.node_types())
    ];
    updated = lower_updates(spec.updates, b, state, node_value, overflow, zero_divisor, reports);
    successor = b.load(b.gep(links, [current]), name="successor");
    next_step = b.add(steps, ir.Constant(i64, 1));
    body_end = b.block;
    b.branch(check);
    current.add_incoming(successor, body_end);
    for (phi, value) in zip(state, updated) {
        phi.add_incoming(value, body_end);
    }
    steps.add_incoming(next_step, body_end);
    b.position_at_end(finish);
    for (value, column) in zip(state, output) {
        store_field(b, value, column, index);
    }
    b.store(ir.Constant(i32, 0), b.gep(status, [index]));
    b.branch(done);
    for (block, code) in (
        (bad_index, 1),
        (cycle, 2),
        (overflow, 3),
        (zero_divisor, 4),
        (report_full, 7)
    ) {
        b.position_at_end(block);
        b.store(ir.Constant(i32, code), b.gep(status, [index]));
        b.branch(done);
    }
    b.position_at_end(done);
    b.ret_void();
}

def emit_chain_ptx(walkers: list[ChainWalker]) -> PtxArtifact {
    if any(hasattr(s, "cursor_names") for s in walkers) {
        import from jaclang.runtime.gpu_cursors { emit_cursor_artifact }
        return emit_cursor_artifact(walkers, 'chain');
    }
    target = ptx_target();
    artifact = emit_ptx_artifact(
        build_chain_module(walkers, target),
        target,
        [spec.metadata() for spec in walkers]
    );
    artifact.format = "jac-ptx-chain-v1";
    artifact.argument_order = "values, next, heads, initial_total, results, status, node_count, walker_count";
    if any(len(spec.field_paths()) > 1 for spec in walkers) {
        artifact.format = "jac-ptx-chain-v2";
        artifact.argument_order = "node field pointers, next, heads, initial_total, results, status, node_count, walker_count; exact order in each kernel's parameters";
    }
    if any(len(spec.state_paths()) > 1 for spec in walkers) {
        artifact.format = "jac-ptx-chain-v3";
        artifact.argument_order = "node fields, next, heads, initial state columns, result state columns, status, node_count, walker_count; exact order in each kernel's parameters";
    }
    if any(has_reports(spec.updates) for spec in walkers) {
        artifact.format = "jac-ptx-chain-v4";
        artifact.argument_order = "exact order in each kernel's parameters; reports append counts, values, capacity";
    }
    if any(spec.typed() for spec in walkers) {
        artifact.format = "jac-ptx-chain-v5";
        artifact.argument_order = "exact typed argument order in each kernel's parameters";
    }
    return artifact;
}
