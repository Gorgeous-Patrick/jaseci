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
