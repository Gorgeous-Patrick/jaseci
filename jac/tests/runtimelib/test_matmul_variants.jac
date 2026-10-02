"""Every standard-library Jac matmul path executes and agrees on CPU."""

import json;
import subprocess;
import tempfile;
import from pathlib { Path }
import from tests.support { TESTS_DIR, jac_command }

test "CPU matmul variants agree with exact and independent decimal references" {
    repo = Path(TESTS_DIR).resolve().parents[1];
    with tempfile.TemporaryDirectory() as directory {
        output = Path(directory) / "verification.json";
        process = subprocess.run(
            jac_command(
                "run",
                "-b",
                "python",
                str(repo / "jac/examples/matmul/validate.jac"),
                "--no-libraries",
                "--json",
                str(output)
            ),
            capture_output=True,
            text=True,
            timeout=180
        );
        assert process.returncode == 0 , process.stdout + process.stderr;
        results = json.loads(output.read_text());
        assert results["cpu_executed"] is True;
        assert results["gpu_executed"] is False;
        assert results["implementation_count"] == 32;
        assert results["case_count"] == 19;
        assert results["configuration_checks"] == 90;
        assert len(
            [
                row
                for row in results["implementations"]
                if row["family"] == "OSP"
            ]
        )
            == 7;
        assert all(
            row["cases_passed"] == 19 and row["invalid_shapes_rejected"] == 6
            for row in results["implementations"]
        );
    }
}
