"""Differential CPU and code-generation checks; no GPU execution is implied."""

import argparse
import ctypes
import itertools
import json
import math
import operator
from pathlib import Path
import random
import struct
import sys

from bootstrap import bootstrap


def sum_steps(a, steps):
    total = 0.0
    while steps > 0.0:
        total += a
        steps -= 1.0
    return total


def test_cases():
    rng = random.Random(612)
    edge = [0.0, -0.0, 1.0, -1.0, 3.25, -7.5, 2.0**40, 2.0**-1074,
            -2.0**-1074, sys.float_info.max, -sys.float_info.max,
            math.inf, -math.inf, math.nan]
    pairs = list(itertools.product(edge, repeat=2))
    pairs += [(rng.uniform(-1e6, 1e6), rng.uniform(-1e6, 1e6)) for _ in range(64)]
    cases = {}
    for name, op in (("add", operator.add), ("sub", operator.sub), ("mul", operator.mul),
                     ("eq", operator.eq), ("ne", operator.ne), ("lt", operator.lt),
                     ("le", operator.le), ("gt", operator.gt), ("ge", operator.ge)):
        cases["float_" + name] = (op, pairs)
    cases["float_neg"] = (operator.neg, [(a,) for a in edge])
    cases["float_pos"] = (operator.pos, [(a,) for a in edge])
    cases["bool_not"] = (operator.not_, [(False,), (True,)])
    cases["bool_and"] = (lambda a, b: a and b, list(itertools.product((False, True), repeat=2)))
    cases["bool_or"] = (lambda a, b: a or b, list(itertools.product((False, True), repeat=2)))
    cases["float_select"] = (lambda c, a, b: a if c else b,
                             [(c, a, b) for c in (False, True) for a, b in pairs[:196]])
    cases["float_clamp"] = (lambda a, lo, hi: lo if a < lo else hi if a > hi else a,
                            [(a, -2.0, 3.0) for a in edge] + [(1.0, math.nan, 4.0)])
    cases["float_mul_add"] = (lambda a, b, c: a * b + c, [
        (1.0 + 2.0**-27, 1.0 - 2.0**-27, -1.0),  # FMA would give a different result.
        (sys.float_info.max, 2.0, -sys.float_info.max),
        (-0.0, 1.0, -0.0), (2.0**-1074, 1.0, 0.0),
    ] + [(a, b, -3.0) for a, b in pairs])
    cases["float_sum_steps"] = (sum_steps, [
        (a, n) for a in (0.0, -0.0, 2.0**-1074, -3.25, 2.0**40, math.nan)
        for n in (0.0, -1.0, 0.5, 1.0, 4.0, 17.0)
    ])
    cases["squared_difference"] = (lambda a, b: (a - b) * (a - b), pairs)
    cases["squared_distance"] = (
        lambda ax, ay, bx, by: (ax - bx) * (ax - bx) + (ay - by) * (ay - by),
        [(a, b, 2.0, -3.0) for a, b in pairs],
    )
    return cases


def assert_same(actual, expected, context):
    if isinstance(expected, bool):
        assert actual == expected, (context, actual, expected)
    elif math.isnan(expected):
        assert math.isnan(actual), (context, actual, expected)
    else:
        # Includes sign of zero, subnormals, infinities, and exact finite bits.
        assert struct.pack("=d", actual) == struct.pack("=d", expected), (context, actual, expected)


def run(args):
    ir, llvm = bootstrap(args.repo, args.shim, args.cache)
    from jaclang.compiler.backends.native.ptx import (
        PtxUnsupported, build_ptx_module, compile_ptx_source, emit_ptx, select_ptx_functions,
    )

    def emit(selection, output):
        artifact = emit_ptx(selection)
        output.mkdir(parents=True, exist_ok=True)
        (output / "scalar.gpu.ll").write_text(artifact.llvm_ir)
        (output / "scalar.ptx").write_text(artifact.ptx)
        return {
            "llvm_version": list(llvm.llvm_version_info),
            "target": "sm_70", "kernels": artifact.kernels,
            "llvm_verified": True, "ptx_emitted": True,
            "fast_math": False, "fma_contraction": False,
        }

    fixtures = args.repo / "jac/tests/compiler/backends/native/fixtures"
    source = fixtures / "ptx_scalar_ops.jac"
    original = compile_ptx_source(str(source))
    cases = test_cases()
    selection = select_ptx_functions(original, list(cases))
    report = emit(selection, args.output)
    (args.output / "scalar.selected.ll").write_text(selection.llvm_ir())
    cpu_target = llvm.Target.from_default_triple().create_target_machine(opt=2)
    cpu_module = build_ptx_module(selection, cpu_target, device=False)
    (args.output / "scalar.cpu-check.ll").write_text(str(cpu_module))
    engine = llvm.create_mcjit_compiler(cpu_module, cpu_target)
    engine.finalize_object()
    scalar_counts, batch_counts = {}, {}
    boundary_checks = 0

    def ctype(typ, *, memory=False):
        if typ == ir.IntType(1):
            return ctypes.c_uint8 if memory else ctypes.c_bool
        return ctypes.c_double

    for function in selection.roots:
        reference, inputs = cases[function.name]
        ret_type = ctype(function.function_type.return_type)
        arg_types = [ctype(t) for t in function.function_type.args]
        address = engine.get_function_address(function.name)
        assert address, function.name
        scalar = ctypes.CFUNCTYPE(ret_type, *arg_types)(address)
        for row in inputs:
            assert_same(scalar(*row), reference(*row), (function.name, row))
        scalar_counts[function.name] = len(inputs)

        # Use different neighboring elements to catch index or stride errors.
        n = len(inputs)
        memory_types = [ctype(t, memory=True) for t in function.function_type.args]
        arrays = [(typ * n)(*(row[i] for row in inputs)) for i, typ in enumerate(memory_types)]
        output_type = ctype(function.function_type.return_type, memory=True)
        sentinel = 173 if output_type == ctypes.c_uint8 else -987654.25
        output = (output_type * (n + 2))(*([sentinel] * (n + 2)))
        out_pointer = ctypes.cast(ctypes.byref(output, ctypes.sizeof(output_type)),
                                  ctypes.POINTER(output_type))
        lane_address = engine.get_function_address(f"jac_{function.name}_lane")
        assert lane_address, function.name
        lane = ctypes.CFUNCTYPE(None, *[ctypes.POINTER(t) for t in memory_types],
                               ctypes.POINTER(output_type), ctypes.c_uint64,
                               ctypes.c_uint64)(lane_address)
        for index in range(n):
            lane(*arrays, out_pointer, n, index)
        for index, row in enumerate(inputs):
            assert_same(output[index + 1], reference(*row), (function.name, "batch", index))
        # Empty batches and out-of-range lanes must not even dereference inputs.
        for count, index in ((0, 0), (n, n), (n, 2**32), (n, 2**64 - 1)):
            lane(*([None] * len(arrays)), None, count, index)
            boundary_checks += 1
        assert output[0] == sentinel and output[-1] == sentinel, function.name
        batch_counts[function.name] = n
        # Canonicalize nonzero boolean input bytes, and always write 0 or 1.
        if function.name == "bool_not":
            data = (ctypes.c_uint8 * 3)(0, 2, 255)
            result = (ctypes.c_uint8 * 3)(173, 173, 173)
            for index in range(3):
                lane(data, result, 3, index)
            assert list(result) == [1, 0, 0]
            boundary_checks += 1

    unsupported = compile_ptx_source(str(fixtures / "ptx_unsupported.jac"))
    rejected = {}
    expectations = {
        "float_div": "__jac_exc_raise", "float_mod": "__jac_exc_raise",
        "float_floor_div": "__jac_exc_raise", "float_pow": "pow",
        "int_add": "float64/bool", "global_read": "global or indirect",
        "helper_div": "helper_div -> float_div", "recursive": "recursive call",
        "with_output": "not supported",
    }
    for name, diagnostic in expectations.items():
        try:
            select_ptx_functions(unsupported, [name])
        except PtxUnsupported as error:
            assert diagnostic in str(error), (name, str(error))
            rejected[name] = str(error)
        else:
            raise AssertionError(f"Unsafe function was accepted: {name}")

    # A changed Jac body must change generated code and the computed result.
    before = emit_ptx(select_ptx_functions(original, ["float_add"]))
    changed_source = args.output / "changed_body.jac"
    changed_source.write_text("def float_add(a: float, b: float) -> float { return a - b; }\n")
    changed = select_ptx_functions(compile_ptx_source(str(changed_source)), ["float_add"])
    emit(changed, args.output / "changed")
    assert (args.output / "changed/scalar.ptx").read_text() != before.ptx
    changed_target = llvm.Target.from_default_triple().create_target_machine(opt=2)
    changed_module = build_ptx_module(changed, changed_target, device=False)
    changed_engine = llvm.create_mcjit_compiler(changed_module, changed_target)
    changed_engine.finalize_object()
    changed_fn = ctypes.CFUNCTYPE(ctypes.c_double, ctypes.c_double, ctypes.c_double)(
        changed_engine.get_function_address("float_add"))
    assert changed_fn(7.0, 2.0) == 5.0

    report.update({
        "cpu_scalar_cases": scalar_counts, "cpu_batch_cases": batch_counts,
        "cpu_scalar_cases_passed": sum(scalar_counts.values()),
        "cpu_batch_cases_passed": sum(batch_counts.values()),
        "batch_boundary_checks_passed": boundary_checks,
        "rejected_operations": rejected, "changed_jac_body_verified": True,
        "comparison": "exact bits except NaN payload/sign; includes signed zero",
        "gpu_executed": False, "walker_lowering_implemented": False,
    })
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in (
        "cpu_scalar_cases_passed", "cpu_batch_cases_passed", "batch_boundary_checks_passed",
        "changed_jac_body_verified", "gpu_executed",
    )}, indent=2))
    print(f"PTX kernels: {len(report['kernels'])}; rejected unsupported entries: {len(rejected)}")
    print(f"Artifacts: {args.output.resolve()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--shim", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    run(parser.parse_args())
