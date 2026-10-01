import re;
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.backends.native.llvm { ir }
import jaclang.compiler.backends.native.llvm.binding as llvm;

class PtxUnsupported(ValueError) {}

obj PtxSelection {
    has roots: list[ir.Function],
        functions: list[ir.Function];

    def llvm_ir -> str {
        return "\n\n".join(str(fn) for fn in self.functions);
    }
}

obj PtxArtifact {
    has ptx: str,
        llvm_ir: str,
        kernels: list[dict[str, any]],
        format: str = "jac-ptx-scalar-v1",
        argument_order: str = "inputs, output, count";
}

def select_ptx_functions(module: ir.Module, names: list[str]) -> PtxSelection {
    if not names or len(set(names)) != len(names) {
        raise PtxUnsupported("Select at least one --gpu-entry, without duplicates");
    }
    scalar_types = (ir.DoubleType(), ir.IntType(1));
    supported = {
        "alloca",
        "load",
        "store",
        "fadd",
        "fsub",
        "fmul",
        "fneg",
        "fcmp",
        "icmp",
        "and",
        "or",
        "xor",
        "br",
        "ret",
        "phi",
        "select",
        "call"
    };
    selected: dict[str, ir.Function] = {};
    active: list[str] = [];

    def reject(reason: str) {
        raise PtxUnsupported(f"{' -> '.join(active)}: {reason}");
    }

    def inspect_fn(fn: ir.Function) -> None {
        name = fn.name;
        if name in active {
            reject(f"recursive call to {name}");
        }
        if name in selected {
            return;
        }
        active.append(name);
        if name.startswith(("__jac_", "llvm.")) or not fn.blocks {
            reject("host runtime, intrinsic, or external call is not supported");
        }
        signature = fn.function_type;
        if signature.var_arg
            or any(
                typ not in scalar_types
                for typ in (signature.return_type, *signature.args)
            ) {
            reject(f"only float64/bool signatures are supported, got {signature}");
        }

        for block in fn.blocks {
            for inst in block.instructions {
                if isinstance(inst, ir.CallInstr) {
                    called = inst.callee;
                    if not isinstance(called, ir.Function) {
                        reject("indirect calls are not supported");
                    }
                    assert isinstance(called, ir.Function);
                    inspect_fn(called);
                }
            }
        }
        for block in fn.blocks {
            for inst in block.instructions {
                assert isinstance(inst, ir.Instruction);
                if inst.opname not in supported {
                    reject(f"unsupported LLVM operation {inst.opname}");
                }
                if getattr(inst, "flags", ()) or getattr(inst, "fastmath", ()) {
                    reject(f"instruction flags are not supported: {inst.opname}");
                }
                if isinstance(inst, ir.AllocaInstr) {
                    if inst.allocated_type not in scalar_types or inst.operands {
                        reject("only single scalar local allocations are supported");
                    }
                } elif inst.opname in ("load", "store") {
                    if not isinstance(inst.operands[-1], ir.AllocaInstr) {
                        reject("global or indirect memory access is not supported");
                    }
                }
            }
        }
        selected[name] = fn;
        active.pop();
    }

    roots: list[ir.Function] = [];
    for name in names {
        if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", name) {
            raise PtxUnsupported(f"Unsupported entry name: {name!r}");
        }
        fn = module.globals.get(name);
        if not isinstance(fn, ir.Function) {
            raise PtxUnsupported(f"Function not found: {name}");
        }
        inspect_fn(fn);
        roots.append(fn);
    }
    return PtxSelection(roots, list(selected.values()));
}

def _storage_type(typ: ir.Type) -> ir.Type {
    return ir.IntType(8) if typ == ir.IntType(1) else typ;
}

def thread_index(module: ir.Module, builder: ir.IRBuilder) -> ir.Value {
    i32 = ir.IntType(32);
    i64 = ir.IntType(64);
    registers: list[ir.Value] = [];
    for register in ("ctaid.x", "ntid.x", "tid.x") {
        name = "llvm.nvvm.read.ptx.sreg." + register;
        intrinsic = module.globals.get(name);
        if intrinsic is None {
            intrinsic = ir.Function(module, ir.FunctionType(i32, []), name);
        }
        assert isinstance(intrinsic, ir.Function);
        registers.append(builder.zext(builder.call(intrinsic, []), i64));
    }
    (block, width, lane) = registers;
    return builder.add(builder.mul(block, width), lane, name="index");
}

def build_ptx_module(
    selection: PtxSelection, target_machine: llvm.TargetMachine, device: bool = True
) -> llvm.ModuleRef {
    module = ir.Module(name="jac_gpu_scalars");
    module.triple = target_machine.triple;
    module.data_layout = str(target_machine.target_data);
    (i1, i8, i32, i64) = [ir.IntType(n) for n in (1, 8, 32, 64)];
    addrspace = 1 if device else 0;
    for fn in selection.roots {
        callee = ir.Function(module, fn.function_type, name=fn.name);
        elements = [_storage_type(t) for t in fn.function_type.args];
        elements.append(_storage_type(fn.function_type.return_type));
        signature = [t.as_pointer(addrspace=addrspace) for t in elements] + [i64];
        if not device {
            signature.append(i64);
        }
        suffix = "batch" if device else "lane";
        kernel = ir.Function(
            module,
            ir.FunctionType(ir.VoidType(), signature),
            name=f"jac_{fn.name}_{suffix}"
        );
        if device {
            kernel.calling_convention = "ptx_kernel";
        }
        arg_names = [f"in{i}" for i in range(len(fn.args))] + ["out", "count", "index"];
        for (arg, arg_name) in zip(kernel.args, arg_names) {
            arg.name = arg_name;
        }
        builder = ir.IRBuilder(kernel.append_basic_block("entry"));
        work = kernel.append_basic_block("work");
        done = kernel.append_basic_block("done");
        count = kernel.args[len(fn.args) + 1];
        if device {
            index = thread_index(module, builder);
        } else {
            index = kernel.args[-1];
        }
        builder.cbranch(builder.icmp_unsigned("<", index, count), work, done);
        builder.position_at_end(work);
        values = [];
        for (pointer, typ) in zip(kernel.args, fn.function_type.args) {
            value = builder.load(builder.gep(pointer, [index]));
            if typ == i1 {
                value = builder.icmp_unsigned("!=", value, ir.Constant(i8, 0));
            }
            values.append(value);
        }
        result: ir.Value = builder.call(callee, values);
        if result.type == i1 {
            result = builder.zext(result, i8);
        }
        builder.store(result, builder.gep(kernel.args[len(fn.args)], [index]));
        builder.branch(done);
        builder.position_at_end(done);
        builder.ret_void();
    }
    linked = llvm.parse_assembly(str(module));
    bodies = llvm.parse_assembly(selection.llvm_ir());
    bodies.triple = module.triple;
    bodies.data_layout = module.data_layout;
    llvm.link_modules(linked, bodies);
    linked.verify();
    unresolved = [
        fn.name
        for fn in linked.functions
        if fn.is_declaration and not fn.name.startswith("llvm.nvvm.read.ptx.sreg.")
    ];
    if unresolved {
        raise PtxUnsupported(f"Unresolved device calls: {unresolved}");
    }
    return linked;
}

def ptx_target -> llvm.TargetMachine {
    llvm.initialize_all_targets();
    llvm.initialize_all_asmprinters();
    return llvm.Target.from_triple("nvptx64-nvidia-cuda").create_target_machine(
        cpu="sm_70", features="+ptx60", opt=2
    );
}

def emit_ptx_artifact(
    module: llvm.ModuleRef, target: llvm.TargetMachine, kernels: list[dict[str, any]]
) -> PtxArtifact {
    module.verify();
    ptx = target.emit_assembly(module);
    assert isinstance(ptx, str);
    if re.search(r"\b(?:fma|mad)\.[^;\n]*\.f64\b", ptx) {
        raise PtxUnsupported("Unexpected contraction of floating-point operations");
    }
    for kernel in kernels {
        if f".entry {kernel['name']}(" not in ptx {
            raise PtxUnsupported(f"Missing PTX entry for {kernel['name']}");
        }
    }
    if re.search(r"\.extern\s+\.func", ptx) {
        raise PtxUnsupported("PTX contains an unresolved external function");
    }
    return PtxArtifact(ptx, str(module), kernels);
}

def emit_ptx(selection: PtxSelection) -> PtxArtifact {
    target = ptx_target();
    module = build_ptx_module(selection, target);
    kernels: list[dict[str, any]] = [];
    for fn in selection.roots {
        kernels.append(
            {
                "name": f"jac_{fn.name}_batch",
                "input_dtypes": [
                    "uint8_bool" if t == ir.IntType(1) else "float64"
                    for t in fn.function_type.args
                ],
                "output_dtype": "uint8_bool"
                    if fn.function_type.return_type == ir.IntType(1)
                    else "float64"
            }
        );
    }
    return emit_ptx_artifact(module, target, kernels);
}

def compile_ptx_frontend(source: str, no_cgen: bool = True) -> uni.Module {
    import from jaclang.compiler.driver.compile_options { CompileOptions }
    import from jaclang.compiler.driver.program { JacProgram }
    import from pathlib { Path }
    prog = JacProgram();
    module = prog.compile(
        file_path=str(Path(source).resolve()),
        options=CompileOptions(
            no_cgen=no_cgen,
            need_full_ast=True,
            force_codespace="native",
            force_target_program=True,
            skip_native_engine=True,
            no_ir_cache=True,
            native_target="",
            native_debug=False,
            rc_debug_codegen=False,
            walker_speculation="off",
            memory_profile="managed",
            na_gc_mode="cycles",
            nogc_enforce_all=False,
            memory_enforce=[],
            memory_exempt=[],
            native_require=[]
        )
    );
    if prog.errors_had {
        raise PtxUnsupported("\n".join(err.pretty_print() for err in prog.errors_had));
    }
    return module;
}

def compile_ptx_source(source: str) -> ir.Module {
    module = compile_ptx_frontend(source, no_cgen=False);
    if module.gen.llvm_ir is None {
        raise PtxUnsupported(f"{source}: no Native LLVM module was produced");
    }
    assert isinstance(module.gen.llvm_ir, ir.Module);
    return module.gen.llvm_ir;
}

def compile_ptx_entries(
    source: str, names: list[str], graph_format: str = 'chain'
) -> PtxArtifact {
    if graph_format not in ('chain', 'csr') {
        raise PtxUnsupported("GPU graph format must be 'chain' or 'csr'");
    }
    if not names or len(set(names)) != len(names) {
        raise PtxUnsupported("Select at least one --gpu-entry, without duplicates");
    }
    module = compile_ptx_frontend(source);
    walkers = {
        arch.name.value
        for arch in module.body
        if isinstance(arch, uni.Archetype) and arch.arch_kind == "walker"
    };
    if any(name in walkers for name in names) {
        if not all(name in walkers for name in names) {
            raise PtxUnsupported("Build scalar functions and walkers separately");
        }
        import from jaclang.compiler.backends.native.ptx_walker {
            select_chain_walkers,
            emit_chain_ptx
        }
        selected = select_chain_walkers(module, names);
        if graph_format == 'csr' {
            import from jaclang.compiler.backends.native.ptx_csr { emit_csr_ptx }
            return emit_csr_ptx(selected);
        }
        return emit_chain_ptx(selected);
    }
    if graph_format == 'csr' {
        raise PtxUnsupported("CSR graph format requires walker entries");
    }
    return emit_ptx(select_ptx_functions(compile_ptx_source(source), names));
}
