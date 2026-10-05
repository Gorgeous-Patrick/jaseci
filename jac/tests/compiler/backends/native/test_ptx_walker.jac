"""CPU semantic comparisons and PTX build coverage; no GPU execution."""

import json;
import runpy;
import subprocess;
import tempfile;
import from jaclang.runtime.runtime { JacRuntime }
import from pathlib { Path }
import from tests.support { TESTS_DIR, jac_command }

glob REPO = Path(TESTS_DIR).resolve().parents[1],
     SOURCE = REPO / "jac/examples/gpu/chain.jac";

test "chain lowering matches serial Jac walkers with private state and permuted layouts" {
    suite = runpy.run_path(str(REPO / "scripts/gpu_walker/verify.py"));
    outer_context = JacRuntime.peek_context();
    outer_base = JacRuntime.get_base_path_dir();
    outer_target = JacRuntime.get_full_target_path();
    with tempfile.TemporaryDirectory() as tmp {
        result = suite["verify"](REPO, Path(tmp));
        assert result["cpu_walker_results"] > 1024;
        assert result["cpu_invalid_graph_checks"] == 8;
        assert len(result["rejected_sources"]) == 12;
        assert result["gpu_executed"] is False;
    }
    assert JacRuntime.peek_context() is outer_context;
    assert JacRuntime.get_base_path_dir() == outer_base;
    assert JacRuntime.get_full_target_path() == outer_target;
}

test "CLI exports a batch walker with a complete graph and state ABI" {
    with tempfile.TemporaryDirectory() as tmp {
        proc = subprocess.run(
            jac_command(
                "build",
                str(SOURCE),
                "--as",
                "ptx",
                "--gpu-entry",
                "ChainSum",
                "-o",
                tmp
            ),
            capture_output=True,
            text=True,
            timeout=180
        );
        assert proc.returncode == 0 , proc.stdout + proc.stderr;
        metadata = json.loads((Path(tmp) / "chain.ptx.json").read_text());
        assert metadata["format"] == "jac-ptx-chain-v1";
        kernel = metadata["kernels"][0];
        assert kernel["walker_type"] == "ChainSum";
        assert kernel["state_field"] == "total";
        assert kernel["node_field"] == "value";
        assert [p["name"] for p in kernel["parameters"]]
            == [
                "values",
                "next",
                "heads",
                "initial_total",
                "results",
                "status",
                "node_count",
                "walker_count"
            ];
        assert ".entry jac_ChainSum_batch(" in (Path(tmp) / "chain.ptx").read_text();
        assert metadata["gpu_executed"] is False;
    }
}

test "walker check only and rejected builds do not write artifacts" {
    import from jaclang.cli.commands.build { build }
    with tempfile.TemporaryDirectory() as tmp {
        out = Path(tmp) / "out";
        assert build(
            str(SOURCE),
            projection="ptx",
            output=str(out),
            check_only=True,
            gpu_entries=[["ChainSum"]]
        )
            == 0;
        assert not out.exists();
        invalid = Path(tmp) / "invalid.jac";
        invalid.write_text(
            SOURCE.read_text().replace(
                "self.total += here.value;", "here.value += 1.0;"
            )
        );
        assert build(
            str(invalid), projection="ptx", output=str(out), gpu_entries=[["ChainSum"]]
        )
            == 1;
        assert not out.exists();
        assert build(
            str(SOURCE),
            projection="ptx",
            output=str(out),
            gpu_entries=[["ChainSum", "ChainSum"]]
        )
            == 1;
        assert not out.exists();
    }
}

test "CLI exports multi-field chain and CSR schemas in kernel argument order" {
    import from jaclang.cli.commands.build { build }
    with tempfile.TemporaryDirectory() as tmp {
        source = REPO / "jac/examples/gpu/multi_field.jac";
        for graph_format in ("chain", "csr") {
            out = Path(tmp) / graph_format;
            assert build(
                str(source),
                projection="ptx",
                output=str(out),
                gpu_entries=[["WeightedSum"]],
                gpu_graph_format=graph_format
            )
                == 0;
            metadata = json.loads((out / "multi_field.ptx.json").read_text());
            assert metadata["format"] == f"jac-ptx-{graph_format}-v2";
            kernel = metadata["kernels"][0];
            assert kernel["node_fields"]
                == ["value", "weight", "position.x", "position.y"];
            assert kernel["node_objects"] == {"position": "Position"};
            assert [p["name"] for p in kernel["parameters"][:4]]
                == ["values", "values_1", "values_2", "values_3"];
        }
    }
}

test "CLI exports all walker state inputs and outputs in v3 manifests" {
    import from jaclang.cli.commands.build { build }
    with tempfile.TemporaryDirectory() as tmp {
        source = REPO / "jac/examples/gpu/walker_fields.jac";
        for graph_format in ("chain", "csr") {
            out = Path(tmp) / graph_format;
            assert build(
                str(source),
                projection="ptx",
                output=str(out),
                gpu_entries=[["Statistics"]],
                gpu_graph_format=graph_format
            )
                == 0;
            metadata = json.loads((out / "walker_fields.ptx.json").read_text());
            assert metadata["format"] == f"jac-ptx-{graph_format}-v3";
            kernel = metadata["kernels"][0];
            paths = ["total", "count", "metrics.weighted", "metrics.last"];
            assert kernel["state_fields"] == paths;
            assert kernel["state_objects"] == {"metrics": "Metrics"};
            state_params = [
                p
                for p in kernel["parameters"]
                if p.get("length") == "walker_count" and "field_path" in p
            ];
            assert [p["field_path"] for p in state_params] == paths * 2;
            assert [p["access"] for p in state_params] == ["read"] * 4 + ["write"] * 4;
        }
    }
}

test "CLI exports CSR walkers with queue limits and rejects scalar CSR builds" {
    import from jaclang.cli.commands.build { build }
    with tempfile.TemporaryDirectory() as tmp {
        out = Path(tmp) / "out";
        source = REPO / "jac/examples/gpu/csr_graph.jac";
        proc = subprocess.run(
            jac_command(
                "build",
                str(source),
                "--as",
                "ptx",
                "--gpu-entry",
                "GraphSum",
                "--gpu-graph-format",
                "csr",
                "-o",
                str(out)
            ),
            capture_output=True,
            text=True,
            timeout=180
        );
        assert proc.returncode == 0 , proc.stdout + proc.stderr;
        metadata = json.loads((out / "csr_graph.ptx.json").read_text());
        assert metadata["format"] == "jac-ptx-csr-v1";
        assert metadata["kernels"][0]["kind"] == "csr_walker";
        assert [p["name"] for p in metadata["kernels"][0]["parameters"]]
            == [
                "values",
                "offsets",
                "targets",
                "heads",
                "initial_total",
                "results",
                "status",
                "queue",
                "node_count",
                "edge_count",
                "walker_count",
                "queue_capacity",
                "max_visits"
            ];
        assert ".entry jac_GraphSum_csr_batch(" in (out / "csr_graph.ptx").read_text();
        assert metadata["gpu_executed"] is False;
        missing = Path(tmp) / 'check-only';
        assert build(
            str(source),
            projection='ptx',
            output=str(missing),
            check_only=True,
            gpu_entries=[['GraphSum']],
            gpu_graph_format='csr'
        )
            == 0;
        assert not missing.exists();
        assert build(
            str(REPO / 'jac/examples/gpu/scalar.jac'),
            projection='ptx',
            output=str(missing),
            gpu_entries=[['multiply_add']],
            gpu_graph_format='csr'
        )
            == 1;
        assert not missing.exists();
        assert build(str(source), gpu_graph_format='csr') == 1;
    }
}

test "CLI exports numeric report buffers in v4 chain and CSR manifests" {
    source = REPO / "jac/examples/gpu/reports.jac";
    for graph_format in ("chain", "csr") {
        with tempfile.TemporaryDirectory() as tmp {
            proc = subprocess.run(
                jac_command(
                    "build", str(source), "--as", "ptx", "--gpu-entry", "Collector",
                    "--gpu-graph-format", graph_format, "-o", tmp
                ),
                capture_output=True,
                text=True,
                timeout=180
            );
            assert proc.returncode == 0 , proc.stdout + proc.stderr;
            metadata = json.loads((Path(tmp) / "reports.ptx.json").read_text());
            assert metadata["format"] == f"jac-ptx-{graph_format}-v4";
            kernel = metadata["kernels"][0];
            assert [p["name"] for p in kernel["parameters"][-3:]]
                == ["report_counts", "report_values", "report_capacity"];
            assert kernel["parameters"][-2]["dtype"] == "int64";
            assert kernel["status_codes"]["7"] == "report_capacity_exceeded";
            assert kernel["reports"]["layout"]
                == "report_values[slot * walker_count + lane]";
        }
    }
}

test "CLI exports boolean fields and tagged reports in v5 manifests" {
    for graph_format in ("chain", "csr") {
        with tempfile.TemporaryDirectory() as tmp {
            proc = subprocess.run(
                jac_command(
                    "build", str(REPO / "jac/examples/gpu/booleans.jac"),
                    "--as", "ptx", "--gpu-entry", "Collector",
                    "--gpu-graph-format", graph_format, "-o", tmp
                ), capture_output=True, text=True, timeout=180
            );
            assert proc.returncode == 0 , proc.stdout + proc.stderr;
            metadata = json.loads((Path(tmp) / "booleans.ptx.json").read_text());
            assert metadata["format"] == f"jac-ptx-{graph_format}-v5";
            parameters = metadata["kernels"][0]["parameters"];
            assert any(p["dtype"] == "bool64" for p in parameters);
            assert [p["name"] for p in parameters[-4:]]
                == ["report_counts", "report_values", "report_capacity", "report_tags"];
        }
    }
}

test "dynamic walker loops emit real backedges for chain and CSR without changing ABI" {
    import from jaclang.compiler.backends.native.ptx { compile_ptx_frontend }
    import from jaclang.compiler.backends.native.ptx_walker { select_chain_walkers, emit_chain_ptx, build_chain_module }
    import from jaclang.compiler.backends.native.ptx_csr { emit_csr_ptx, build_csr_module }
    import from jaclang.compiler.backends.native.llvm { binding as llvm }
    llvm.initialize_all_targets();
    llvm.initialize_all_asmprinters();
    source = REPO / "jac/examples/gpu/loops.jac";
    specs = select_chain_walkers(compile_ptx_frontend(str(source)), ["LoopSum"]);
    host = llvm.Target.from_default_triple().create_target_machine(opt=2);
    for build_module in [build_chain_module, build_csr_module] {
        module = build_module(specs, host, device=False);
        module.verify();
        text = str(module);
        assert "loop.check" in text;
        assert "loop.state" in text;
        assert text.count("br label %loop.check") >= 2;
    }
    for emit in [emit_chain_ptx, emit_csr_ptx] {
        artifact = emit(specs);
        assert "LoopSum" in artifact.ptx;
        assert len([p for p in artifact.kernels[0]["parameters"] if p.get("field_path") == "total"]) == 2;
        assert all("remaining" not in p["name"] for p in artifact.kernels[0]["parameters"]);
    }
}
