"""Test JavaScript code generation using consolidated Jac fixtures."""

import os
import subprocess
import tempfile
from pathlib import Path

from jaclang.compiler.passes.ecmascript import EsastGenPass
from jaclang.compiler.passes.ecmascript.es_unparse import es_to_js
from jaclang.compiler.program import JacProgram
from jaclang.utils.test import TestCase


class JavaScriptGenerationTests(TestCase):
    """Validate JavaScript generation for core and advanced Jac fixtures."""

    CORE_FIXTURE = "core_language_features.jac"
    ADVANCED_FIXTURE = "advanced_language_features.jac"
    CLIENT_FIXTURE = "client_jsx.jac"

    def get_fixture_path(self, filename: str) -> str:
        """Return absolute path to a fixture file."""
        fixtures_dir = Path(__file__).parent / "fixtures"
        return str(fixtures_dir / filename)

    def compile_fixture_to_js(self, fixture_name: str) -> str:
        """Compile a Jac fixture to JavaScript and return the emitted source."""
        fixture_path = fixture_name
        if not Path(fixture_path).exists():
            fixture_path = self.get_fixture_path(fixture_name)
        prog = JacProgram()
        ir = prog.compile(file_path=fixture_path, no_cgen=True)

        self.assertFalse(
            prog.errors_had,
            f"Compilation errors in {fixture_name}: {[str(e) for e in prog.errors_had]}",
        )

        es_pass = EsastGenPass(ir, prog)
        es_ir = es_pass.ir_out

        self.assertTrue(hasattr(es_ir.gen, "es_ast"), "es_ast attribute missing")
        self.assertIsNotNone(es_ir.gen.es_ast, "es_ast should not be None")

        return es_to_js(es_ir.gen.es_ast)

    def assert_balanced_syntax(self, js_code: str, fixture_name: str) -> None:
        """Ensure generated JavaScript has balanced delimiters."""
        pairs = [("{", "}"), ("(", ")"), ("[", "]")]
        for open_char, close_char in pairs:
            self.assertEqual(
                js_code.count(open_char),
                js_code.count(close_char),
                f"{fixture_name} produced unbalanced {open_char}{close_char} pairs",
            )

    def assert_no_jac_keywords(self, js_code: str, fixture_name: str) -> None:
        """Verify Jac-specific keywords are absent from generated JavaScript."""
        jac_keywords = [
            "can ",
            "has ",
            "obj ",
            "walker ",
            "node ",
            "edge ",
            "visit ",
            "spawn ",
            "disengage ",
            "here ",
            "root ",
        ]

        for keyword in jac_keywords:
            self.assertNotIn(
                keyword,
                js_code,
                f"Jac keyword '{keyword.strip()}' leaked into JavaScript for {fixture_name}",
            )

    def test_core_fixture_emits_expected_constructs(self) -> None:
        """Core fixture should cover fundamental language constructs."""
        js_code = self.compile_fixture_to_js(self.CORE_FIXTURE)

        self.assertIn("const global_counter = 0;", js_code)
        self.assertIn("function add", js_code)
        self.assertIn("function greet", js_code)
        self.assertIn("function fibonacci", js_code)
        self.assertIn("for (const i of range(limit))", js_code)
        self.assertIn("while (counter > 0)", js_code)

        # Operators map to JavaScript equivalents
        self.assertIn("===", js_code)
        self.assertIn("!==", js_code)
        self.assertIn("&&", js_code)
        self.assertIn("||", js_code)

        # Classes and enums materialize as expected
        self.assertIn("class Person", js_code)
        self.assertIn("class Employee extends Person", js_code)
        self.assertIn("class Calculator", js_code)
        self.assertIn("class MathUtils", js_code)
        self.assertIn("const Status", js_code)
        self.assertIn("const Priority", js_code)

        # Exception handling remains intact
        self.assertIn("try", js_code)
        self.assertIn("catch (err)", js_code)
        self.assertIn("finally", js_code)

        self.assert_balanced_syntax(js_code, self.CORE_FIXTURE)
        self.assert_no_jac_keywords(js_code, self.CORE_FIXTURE)
        self.assertGreater(len(js_code), 200, "Core fixture generated suspiciously small output")

    def test_advanced_fixture_emits_expected_constructs(self) -> None:
        """Advanced fixture should exercise higher-level Jac features."""
        js_code = self.compile_fixture_to_js(self.ADVANCED_FIXTURE)

        self.assertIn("function lambda_examples", js_code)
        self.assertIn("async function fetch_value", js_code)
        self.assertIn("await fetch_value", js_code)
        self.assertIn("async function gather_async", js_code)
        self.assertIn("function generator_examples", js_code)
        self.assertIn("function spread_and_rest_examples", js_code)
        self.assertIn("...defaults", js_code)
        self.assertIn("function template_literal_examples", js_code)
        self.assertIn("score >= 60 ? \"pass\" : \"fail\"", js_code)
        self.assertIn("function do_while_simulation", js_code)
        self.assertIn("function build_advanced_report", js_code)

        # Ensure pattern matching lowered into a callable
        self.assertIn("function pattern_matching_examples", js_code)

        self.assert_balanced_syntax(js_code, self.ADVANCED_FIXTURE)
        self.assert_no_jac_keywords(js_code, self.ADVANCED_FIXTURE)
        self.assertGreater(len(js_code), 150, "Advanced fixture output unexpectedly small")

    def test_client_fixture_generates_client_bundle(self) -> None:
        """Client-focused fixture should emit JSX-flavoured JavaScript."""
        js_code = self.compile_fixture_to_js(self.CLIENT_FIXTURE)

        self.assertIn('const API_URL = "https://api.example.com";', js_code)
        self.assertIn("function component()", js_code)
        self.assertIn('__jacJsx("div"', js_code)
        self.assertIn("class ButtonProps", js_code)
        self.assertIn("constructor(props", js_code)
        self.assertNotIn("server_only", js_code, "Server-only code leaked into client bundle")

        self.assert_balanced_syntax(js_code, self.CLIENT_FIXTURE)

    def test_cli_js_command_outputs_js(self) -> None:
        """jac js CLI should emit JavaScript for the core fixture."""
        fixture_path = self.get_fixture_path(self.CORE_FIXTURE)
        env = os.environ.copy()
        project_root = str(Path(__file__).resolve().parents[4])
        existing = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = f"{project_root}:{existing}" if existing else project_root

        result = subprocess.run(
            ["python3", "-m", "jaclang.cli.cli", "js", fixture_path],
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(result.returncode, 0, f"CLI command failed: {result.stderr}")
        self.assertGreater(len(result.stdout), 0, "CLI produced no output")
        self.assertIn("function add", result.stdout)

    def test_empty_file_generates_minimal_js(self) -> None:
        """Ensure an empty Jac file generates a minimal JavaScript stub."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as tmp:
            tmp.write('"""Empty file for smoke testing."""\n')
            temp_path = tmp.name

        try:
            js_code = self.compile_fixture_to_js(temp_path)
            self.assertLess(len(js_code), 100, "Empty file produced unexpectedly large output")
            self.assert_balanced_syntax(js_code, temp_path)
        finally:
            os.unlink(temp_path)
