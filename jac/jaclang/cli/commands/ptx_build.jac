import hashlib;
import json;
import from pathlib { Path }
import from jaclang.cli.console { console }

def ptx_build(
    filename: str,
    entries: list[str],
    output: str,
    check_only: bool = False,
    graph_format: str = 'chain'
) -> int {
    source = Path(filename);
    if source.suffix != ".jac" or not source.is_file() {
        console.error("PTX builds require an existing .jac file.");
        return 1;
    }
    if not entries {
        console.error(
            "PTX builds require --gpu-entry FUNCTION_OR_WALKER (repeatable)."
        );
        return 1;
    }

    import from jaclang.compiler.backends.native.ptx { compile_ptx_entries }
    try {
        artifact = compile_ptx_entries(str(source), entries, graph_format);
        if check_only {
            console.print(
                f"PTX checks passed for {len(entries)} kernel(s); no files emitted."
            );
            return 0;
        }
        dest = Path(output);
        dest.mkdir(parents=True, exist_ok=True);
        prefix = dest / source.stem;
        manifest = {
            "format": artifact.format,
            "source": str(source.resolve()),
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "target": "sm_70",
            "ptx_feature": "ptx60",
            "kernels": artifact.kernels,
            "count_dtype": "uint64",
            "launch_dimensions": 1,
            "argument_order": artifact.argument_order,
            "fast_math": False,
            "fma_contraction": False,
            "gpu_executed": False
        };

        Path(str(prefix) + ".ptx").write_text(artifact.ptx);
        Path(str(prefix) + ".gpu.ll").write_text(artifact.llvm_ir);
        Path(str(prefix) + ".ptx.json").write_text(
            json.dumps(manifest, indent=2) + "\n"
        );
        console.print(
            f"Emitted {prefix}.ptx ({len(
                entries
            )} kernel(s); GPU execution not performed)."
        );
        return 0;
    } except (ValueError, RuntimeError, OSError) as error {
        console.error(f"PTX build failed for {source}: {error}");
        return 1;
    }
}
