# Jac PTX scalar verification

PTX generation lives in `jaclang.compiler.backends.native.ptx` and is exposed
through `jac build --as ptx`. These scripts only provide differential verification
using the same backend; they do not implement a second compiler.

```bash
jac build jac/examples/gpu/scalar.jac --as ptx \
  --gpu-entry multiply_add --gpu-entry within_radius --gpu-entry distance_squared \
  -o /tmp/jac-ptx-example
```

This emits `scalar.ptx`, `scalar.gpu.ll`, and `scalar.ptx.json`. The JSON describes
each kernel's array argument types, output, and element count. It is device code,
not an executable application. The compiler uses Jac's existing LLVM bindings;
the selected LLVM build must include NVPTX. The current target is sm_70 / PTX 6.0.

## Reproduce the differential checks

From the repository root, using a Python compatible with the source compiler:

```bash
python3 -B scripts/gpu_scalar/verify.py \
  --shim /absolute/path/to/libjacllvm.so \
  --cache /tmp/jac-gpu-compiler-cache \
  --output /tmp/jac-ptx-verification
```

The first run may bootstrap the source compiler. The cache is reusable. No CUDA
host-library choice, network install, or available GPU is required for these
checks. Generated artifacts go only into the requested output directory.

The verifier covers 20 float64/bool functions: addition, subtraction,
multiplication, unary signs, six comparisons, boolean operations, conditional
selection, branches, a loop, and a multi-level helper call graph. It checks
normal values, subnormals, NaN, infinities, signed zeros, overflow to infinity,
and a case where fused multiply-add would change rounding. Results are compared
bit for bit except for NaN payload and sign.

Checks distinguish three levels of evidence:

1. LLVM verification and PTX emission for every exported kernel.
2. CPU execution of the same selected Jac-generated bodies and batch load/store
   generation, including empty/out-of-range lanes and byte boolean storage.
3. Actual CUDA loading, execution, and performance: **not performed**.

Negative cases reject Jac division/modulo exception paths, external math calls,
integer arithmetic, global state, recursion, and printing. Changing a Jac body
must change generated PTX and its CPU result. The regular regression tests live
in `jac/tests/compiler/backends/native/test_ptx.jac` and exercise the actual CLI.

## Current boundary

This verifier covers scalar PTX output. The separate
[chain-walker verifier](../gpu_walker/README.md) covers restricted walker lowering.
Selected scalar functions use
only float64/bool values and private scalar locals; helpers must be direct,
acyclic, and defined in the same module. Unsupported operations produce errors
rather than using a CPU fallback or losing exception checks. The containing
module is type-checked, but its entry block and unrelated functions are not run.

No fast-math flags are added. The backend leaves process-wide LLVM options
unchanged and rejects emitted floating FMA/MAD instructions. LLVM's NVPTX
implementation documents its contraction conditions in
[NVPTXISelLowering.cpp](https://github.com/llvm/llvm-project/blob/release/22.x/llvm/lib/Target/NVPTX/NVPTXISelLowering.cpp).

Batch kernels use one-dimensional launches. Each input and output array needs
at least `count` elements; output storage must not overlap input storage. The
index multiplication is widened to 64 bits before the bounds check. Loops are
not made terminating by compilation; provide inputs for which the Jac program
terminates.
