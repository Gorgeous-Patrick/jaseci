# Jac research results

[English PDF slides](jac-transformer-and-gpu-results.pdf) contain two sections:
Transformer on Jac and Jac on GPU. They cover the preserved module model,
new primitive dataflow model, reusable runtime library, FX/Inductor lowering,
lazy Cond dependency extraction and correctness tests, cursor-concatenated packing, and complete
3000 × 3000 × 3000 scalar-node MatMul experiment.

Regenerate from the repository root with Python and Matplotlib:

```sh
MPLCONFIGDIR=/tmp/jac-slides-mpl python docs/presentations/jac-research-results/generate.py
```

`sources.json` lists the repository evidence used. Charts read saved measurement
JSON; graph diagrams use actual exported nodes and edges. No HTML is generated.
The deck distinguishes correctness from performance, event timings from pure
kernel timings, theoretical sectors from hardware counters, and observed
performance from unmeasured causal explanations. Measurement environments and
the large run's interrupted interpreter cleanup are disclosed.

Raw multi-gigabyte GPU buffers and profiler binaries remain on the measurement
host; compact reports and reproduction scripts are checked in.
