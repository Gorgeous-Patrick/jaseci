"""PTX emission, CPU differential checks, and command integration without a GPU."""

import ctypes;
import json;
import math;
import subprocess;
import tempfile;
import from pathlib { Path }
import from tests.support { TESTS_DIR, jac_command }
import from jaclang.compiler.backends.native.ptx {
    PtxUnsupported,
    compile_ptx_source,
    select_ptx_functions,
    emit_ptx,
    build_ptx_module
}
import jaclang.compiler.backends.native.llvm.binding as llvm;

glob FIXTURES = Path(TESTS_DIR) / "compiler/backends/native/fixtures",
     _modules: dict[str, any] = {};

def fixture(name: str = "ptx_scalar_ops.jac") -> any {
    if name not in _modules {
        _modules[name] = compile_ptx_source(str(FIXTURES / name));
    }
    return _modules[name];
}

test "PTX selects helper closure and exports only requested batch entries" {
    selection = select_ptx_functions(fixture(), ["squared_distance"]);
    assert {fn.name for fn in selection.functions}
        == {
            "squared_distance",
            "squared_difference",
            "float_sub",
            "float_mul",
            "float_add"
        };
    artifact = emit_ptx(selection);
    assert ".entry jac_squared_distance_batch(" in artifact.ptx;
    assert ".entry jac_float_sub_batch(" not in artifact.ptx;
    assert "__jac_exc_raise" not in artifact.ptx;
    assert "fma.rn.f64" not in artifact.ptx;
    assert artifact.kernels[0]["input_dtypes"] == ["float64"] * 4;
}

test "PTX preserves NaN comparisons signed zero and separate multiply add" {
    llvm.initialize_all_targets();
    llvm.initialize_all_asmprinters();
    selection = select_ptx_functions(
        fixture(), ["float_ne", "float_neg", "float_mul_add"]
    );
    emit_ptx(selection);
    target = llvm.Target.from_default_triple().create_target_machine();
    module = build_ptx_module(selection, target, device=False);
    engine = llvm.create_mcjit_compiler(module, target);
    engine.finalize_object();
    ne = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_double, ctypes.c_double)(
        engine.get_function_address("float_ne")
    );
    neg = ctypes.CFUNCTYPE(ctypes.c_double, ctypes.c_double)(
        engine.get_function_address("float_neg")
    );
    mul_add = ctypes.CFUNCTYPE(
        ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_double
    )(
        engine.get_function_address("float_mul_add")
    );
    assert ne(float("nan"), 1.0);
    assert ne(float("nan"), float("nan"));
    assert math.copysign(1.0, neg(0.0)) == -1.0;
    assert mul_add(1.0 + 2.0 ** -27, 1.0 - 2.0 ** -27, -1.0) == 0.0;
}

test "PTX rejects runtime calls globals recursion and unsupported signatures" {
    mod = fixture("ptx_unsupported.jac");
    cases = {
        "float_div": "__jac_exc_raise",
        "float_mod": "__jac_exc_raise",
        "float_floor_div": "__jac_exc_raise",
        "float_pow": "pow",
        "int_add": "float64/bool",
        "global_read": "global or indirect",
        "helper_div": "helper_div -> float_div",
        "recursive": "recursive call",
        "with_output": "not supported"
    };
    for (name, diagnostic) in cases.items() {
        with testraises(PtxUnsupported) as exc {
            select_ptx_functions(mod, [name]);
        }
        assert diagnostic in str(exc.value) , str(exc.value);
    }
    for names in ([], ["missing"], ["float_add", "float_add"]) {
        with testraises(PtxUnsupported) {
            select_ptx_functions(fixture(), names);
        }
    }
}

test "jac build emits PTX through the CLI with repeated entry flags" {
    with tempfile.TemporaryDirectory() as tmp {
        proc = subprocess.run(
            jac_command(
                "build",
                str(FIXTURES / "ptx_scalar_ops.jac"),
                "--as",
                "ptx",
                "--gpu-entry",
                "float_add",
                "--gpu-entry",
                "float_lt",
                "-o",
                tmp
            ),
            capture_output=True,
            text=True,
            timeout=120
        );
        assert proc.returncode == 0 , proc.stdout + proc.stderr;
        manifest = json.loads((Path(tmp) / "ptx_scalar_ops.ptx.json").read_text());
        assert len(manifest["kernels"]) == 2;
        assert manifest["kernels"][1]["output_dtype"] == "uint8_bool";
        assert manifest["gpu_executed"] is False;
        ptx = (Path(tmp) / "ptx_scalar_ops.ptx").read_text();
        assert ".entry jac_float_add_batch(" in ptx;
        assert ".entry jac_float_lt_batch(" in ptx;
    }
}

test "PTX build rejects invalid flags and unsupported programs without artifacts" {
    import from jaclang.cli.commands.build { build }
    with tempfile.TemporaryDirectory() as tmp {
        src = str(FIXTURES / "ptx_unsupported.jac");
        assert build(src, projection="ptx", output=tmp, gpu_entries=[["float_div"]])
            == 1;
        assert build(src, projection="ptx", output=tmp) == 1;
        assert build(
            src, projection="ptx", output=tmp, native=True, gpu_entries=[["float_div"]]
        )
            == 1;
        assert build(src, output=tmp, gpu_entries=[["float_div"]]) == 1;
        assert not list(Path(tmp).iterdir());
    }
}

test "PTX check only validates selected functions without writing files" {
    import from jaclang.cli.commands.build { build }
    with tempfile.TemporaryDirectory() as tmp {
        out = Path(tmp) / "output";
        src = str(FIXTURES / "ptx_scalar_ops.jac");
        assert build(
            src,
            projection="ptx",
            output=str(out),
            check_only=True,
            gpu_entries=[["float_mul"]]
        )
            == 0;
        assert not out.exists();
    }
}
