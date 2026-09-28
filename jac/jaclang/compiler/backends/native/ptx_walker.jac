import math;
import re;
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.types.types { ClassType }
import from jaclang.runtime.constants { EdgeDir }
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
        value: float = 0.0,
        left: ChainExpr | None = None,
        right: ChainExpr | None = None;

    def lower(b: ir.IRBuilder, state: ir.Value, node_value: ir.Value) -> ir.Value {
        if self.op == "state" {
            return state;
        }
        if self.op == "node" {
            return node_value;
        }
        if self.op == "constant" {
            return ir.Constant(ir.DoubleType(), self.value);
        }
        assert self.left is not None;
        left = self.left.lower(b, state, node_value);
        if self.op == "neg" {
            return b.fneg(left);
        }
        assert self.right is not None;
        right = self.right.lower(b, state, node_value);
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

obj ChainWalker {
    has name: str,
        node_type: str,
        edge_type: str,
        node_field: str,
        state_field: str,
        default_total: float,
        update: ChainExpr;

    def metadata -> dict[str, any] {
        return {
            "name": f"jac_{self.name}_batch",
            "kind": "chain_walker",
            "walker_type": self.name,
            "node_type": self.node_type,
            "edge_type": self.edge_type,
            "node_field": self.node_field,
            "state_field": self.state_field,
            "default_initial_state": self.default_total,
            "parameters": [
                {
                    "name": "values",
                    "dtype": "float64",
                    "length": "node_count",
                    "access": "read"
                },
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
                {
                    "name": "initial_total",
                    "dtype": "float64",
                    "length": "walker_count",
                    "access": "read"
                },
                {
                    "name": "results",
                    "dtype": "float64",
                    "length": "walker_count",
                    "access": "write"
                },
                {
                    "name": "status",
                    "dtype": "uint32",
                    "length": "walker_count",
                    "access": "write"
                },
                {"name": "node_count", "dtype": "uint64"},
                {"name": "walker_count", "dtype": "uint64"}
            ],
            "null_node": -1,
            "status_codes": {"0": "success", "1": "invalid_node_index", "2": "cycle"},
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

def one_float_field(arch: uni.Archetype) -> uni.HasVar {
    fields = arch.get_has_vars();
    if len(fields) != 1 {
        reject(arch, "GPU chains require exactly one float field per node/walker");
    }
    field = fields[0];
    typ = field.type;
    if field.type_tag is None
        or not isinstance(typ, ClassType)
        or not typ.is_builtin("float") {
        reject(field, "GPU chain fields must have checked float64 types");
    }
    owner = field.parent;
    if not isinstance(owner, uni.ArchHas)
        or owner.is_static
        or owner.is_frozen
        or field.defer
        or field.accessors {
        reject(field, "GPU chains require ordinary instance fields without accessors");
    }
    return field;
}

def field_ref(expr: uni.Expr, receiver: str, field: uni.HasVar) -> bool {
    return isinstance(expr, uni.AtomTrailer)
        and expr.is_attr
        and not expr.is_null_ok
        and not expr.is_genai
        and isinstance(expr.target, uni.SpecialVarRef)
        and expr.target.value == receiver
        and isinstance(expr.right, uni.Name)
        and expr.right.value == field.name.value
        and expr.right.sym is not None
        and expr.right.sym is field.name.sym;
}

def chain_expr(expr: uni.Expr, state: uni.HasVar, nd: uni.HasVar) -> ChainExpr {
    if isinstance(expr, uni.AtomUnit) and isinstance(expr.value, uni.Expr) {
        return chain_expr(expr.value, state, nd);
    }
    if isinstance(expr, uni.Float) {
        return ChainExpr("constant", value=expr.lit_value);
    }
    if field_ref(expr, "self", state) {
        return ChainExpr("state");
    }
    if field_ref(expr, "here", nd) {
        return ChainExpr("node");
    }
    if isinstance(expr, uni.UnaryExpr) and expr.op.value in ("+", "-") {
        operand = chain_expr(expr.operand, state, nd);
        return operand if expr.op.value == "+" else ChainExpr("neg", left=operand);
    }
    if isinstance(expr, uni.BinaryExpr)
        and isinstance(expr.op, uni.Token)
        and expr.op.value in ("+", "-", "*") {
        return ChainExpr(
            expr.op.value,
            left=chain_expr(expr.left, state, nd),
            right=chain_expr(expr.right, state, nd)
        );
    }
    reject(
        expr,
        "GPU chain expressions support float literals, self/here fields, and +, -, * only"
    );
    raise AssertionError("unreachable");
}

def literal_default(field: uni.HasVar) -> float {
    value = field.value;
    sign = 1.0;
    if isinstance(value, uni.UnaryExpr) and value.op.value in ("+", "-") {
        sign = -1.0 if value.op.value == "-" else 1.0;
        value = value.operand;
    }
    if not isinstance(value, uni.Float) or not math.isfinite(value.lit_value) {
        reject(field, "GPU walker state requires a finite float literal default");
    }
    assert isinstance(value, uni.Float);
    return sign * value.lit_value;
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
        plain_archetype(arch);
        state = one_float_field(arch);
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
        node_field = one_float_field(nd);
        if any(not isinstance(s, uni.ArchHas) for s in nd.body) {
            reject(
                nd,
                "Node abilities and other node behavior are not supported by GPU chains"
            );
        }
        body = ability.body;
        if not isinstance(body, list)
            or len(body) != 2
            or not isinstance(body[0], uni.Assignment)
            or not isinstance(body[1], uni.VisitStmt) {
            reject(
                ability,
                "GPU chain body must contain one state update followed by one tail visit"
            );
        }
        update = body[0];
        visit_stmt = body[1];
        assert isinstance(update, uni.Assignment)
            and isinstance(visit_stmt, uni.VisitStmt);
        if len(update.target) != 1
            or not field_ref(update.target[0], "self", state)
            or not isinstance(update.value, uni.Expr) {
            reject(update, "GPU chains only write the private walker field");
        }
        assert isinstance(update.value, uni.Expr);
        expression = chain_expr(update.value, state, node_field);
        if update.aug_op is not None {
            op = update.aug_op.value;
            if op not in ("+=", "-=", "*=") {
                reject(update, "Unsupported GPU chain assignment");
            }
            expression = ChainExpr(op[0], left=ChainExpr("state"), right=expression);
        }
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
                node_field.name.value,
                state.name.value,
                literal_default(state),
                expression
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
    space = 1 if device else 0;
    signature = [t.as_pointer(addrspace=space) for t in (f64, i64, i64, f64, f64, i32)]
        + [i64, i64];
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
        fn.args,
        (
            "values",
            "next",
            "heads",
            "initial_total",
            "results",
            "status",
            "node_count",
            "walker_count",
            "index"
        )
    ) {
        arg.name = name;
    }
    (values, links, heads, initial, output, status, node_count, count) = fn.args[:8];
    entry_bb = fn.append_basic_block("entry");
    start = fn.append_basic_block("start");
    check = fn.append_basic_block("chain.check");
    bounds = fn.append_basic_block("node.bounds");
    limit = fn.append_basic_block("cycle.check");
    body = fn.append_basic_block("ability");
    finish = fn.append_basic_block("finish");
    bad_index = fn.append_basic_block("invalid.node");
    cycle = fn.append_basic_block("cycle");
    done = fn.append_basic_block("done");
    b = ir.IRBuilder(entry_bb);
    index = thread_index(module, b) if device else fn.args[-1];
    b.cbranch(b.icmp_unsigned("<", index, count), start, done);
    b.position_at_end(start);
    head = b.load(b.gep(heads, [index]));
    seed = b.load(b.gep(initial, [index]));
    b.branch(check);
    b.position_at_end(check);
    current = b.phi(i64, name="current");
    total = b.phi(f64, name=spec.state_field);
    steps = b.phi(i64, name="steps");
    current.add_incoming(head, start);
    total.add_incoming(seed, start);
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
    node_value = b.load(b.gep(values, [current]), name=spec.node_field);
    updated = spec.update.lower(b, total, node_value);
    successor = b.load(b.gep(links, [current]), name="successor");
    next_step = b.add(steps, ir.Constant(i64, 1));
    b.branch(check);
    current.add_incoming(successor, body);
    total.add_incoming(updated, body);
    steps.add_incoming(next_step, body);
    b.position_at_end(finish);
    b.store(total, b.gep(output, [index]));
    b.store(ir.Constant(i32, 0), b.gep(status, [index]));
    b.branch(done);
    for (block, code) in ((bad_index, 1), (cycle, 2)) {
        b.position_at_end(block);
        b.store(ir.Constant(i32, code), b.gep(status, [index]));
        b.branch(done);
    }
    b.position_at_end(done);
    b.ret_void();
}

def emit_chain_ptx(walkers: list[ChainWalker]) -> PtxArtifact {
    target = ptx_target();
    artifact = emit_ptx_artifact(
        build_chain_module(walkers, target),
        target,
        [spec.metadata() for spec in walkers]
    );
    artifact.format = "jac-ptx-chain-v1";
    artifact.argument_order = "values, next, heads, initial_total, results, status, node_count, walker_count";
    return artifact;
}
