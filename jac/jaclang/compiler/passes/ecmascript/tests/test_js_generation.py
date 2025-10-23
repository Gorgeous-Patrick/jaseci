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

    def test_iife_fixture_generates_function_expressions(self) -> None:
        """IIFE-heavy fixture should lower Jac function expressions for JS runtime."""
        fixture_path = self.lang_fixture_abs_path("iife_functions_client.jac")
        js_code = self.compile_fixture_to_js(fixture_path)

        # Ensure representative IIFE constructs are present
        self.assertIn("function get_value()", js_code)
        self.assertIn("function calculate(x, y)", js_code)
        self.assertIn("}();", js_code, "IIFE invocation pattern missing in generated JS")
        self.assertIn("function outer()", js_code)
        # Verify closure is working correctly - count should not be redeclared with 'let'
        # The inner function should access the outer 'count' variable via closure
        self.assertIn("return () => {\n    count = count + 1;\n    return count;\n  };", js_code)
        self.assertIn("All client-side IIFE tests completed!", js_code)

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

    def test_type_to_typeof_transformation(self) -> None:
        """Test that type() calls transform to typeof operator in JavaScript."""
        jac_code = '''"""Test type() to typeof conversion."""

cl def check_types() {
    let x = 42;
    let y = "hello";
    let obj = {"key": "value"};
    let arr = [1, 2, 3];

    let t1 = type(x);
    let t2 = type(y);
    let t3 = type(obj);
    let t4 = type(arr[0]);

    return t1;
}
'''
        with tempfile.NamedTemporaryFile(mode="w", suffix=".jac", delete=False) as tmp:
            tmp.write(jac_code)
            tmp.flush()
            temp_path = tmp.name

        try:
            js_code = self.compile_fixture_to_js(temp_path)

            # Verify typeof operator is present
            self.assertIn("typeof", js_code, "typeof operator should be present in output")

            # Verify specific transformations
            self.assertIn("typeof x", js_code, "type(x) should become typeof x")
            self.assertIn("typeof y", js_code, "type(y) should become typeof y")
            self.assertIn("typeof obj", js_code, "type(obj) should become typeof obj")
            self.assertIn("typeof arr[0]", js_code, "type(arr[0]) should become typeof arr[0]")

            # Ensure no type() function calls remain
            self.assertNotIn("type(", js_code, "No type() calls should remain in JavaScript")

            # Count typeof occurrences - should have exactly 4
            typeof_count = js_code.count("typeof")
            self.assertEqual(typeof_count, 4, f"Expected 4 typeof occurrences, found {typeof_count}")

            self.assert_balanced_syntax(js_code, temp_path)
        finally:
            os.unlink(temp_path)

    def test_category1_named_imports_generate_correct_js(self) -> None:
        """Test Category 1 named imports from proposal document.

        Validates:
        - Single named import: import { useState } from 'react'
        - Multiple named imports: import { a, b, c } from 'lib'
        - Named import with alias: import { foo as bar } from 'lib'
        - Relative path imports with ../ and ./
        - Module prefix notation (jac:client_runtime)
        """
        fixture_path = self.get_fixture_path("category1_named_imports.jac")
        js_code = self.compile_fixture_to_js(fixture_path)

        # Test 1: Single named import
        self.assertIn(
            'import { useState } from "react";',
            js_code,
            "Single named import should generate: import { useState } from 'react';"
        )

        # Test 2: Multiple named imports
        self.assertIn(
            'import { map, filter, reduce } from "lodash";',
            js_code,
            "Multiple named imports should generate: import { map, filter, reduce } from 'lodash';"
        )

        # Test 3: Named import with alias
        self.assertIn(
            'import { get as httpGet } from "axios";',
            js_code,
            "Aliased import should generate: import { get as httpGet } from 'axios';"
        )

        # Test 4: Mixed named imports and aliases
        self.assertIn(
            'import { createApp, ref as reactive, computed } from "vue";',
            js_code,
            "Mixed imports should preserve order and aliases"
        )

        # Test 5: Relative path imports (single dot)
        self.assertIn(
            'import { helper } from "./utils";',
            js_code,
            "Relative import with .utils should generate ./utils"
        )

        # Test 6: Relative path imports (double dot)
        self.assertIn(
            'import { formatter as format } from "../lib";',
            js_code,
            "Relative import with ..lib should generate ../lib"
        )

        # Test 7: Relative path imports (triple dot - grandparent)
        self.assertIn(
            'import { settings } from "../../config";',
            js_code,
            "Relative import with ...config should generate ../../config"
        )

        # Test 8: Module prefix notation (jac:client_runtime)
        # NOTE: Current implementation strips the jac: prefix and generates "client_runtime"
        # This may be intentional for runtime resolution
        self.assertIn(
            'import { renderJsxTree, jacLogin, jacLogout } from "client_runtime";',
            js_code,
            "Module prefix notation resolves to client_runtime"
        )

        # Test 9: Ensure function definitions are generated
        self.assertIn(
            "function example_usage()",
            js_code,
            "Client function should be generated"
        )

        # Test 10: Verify no Python-style imports leaked
        self.assertNotIn("from react import", js_code, "No Python syntax should appear")
        self.assertNotIn("from lodash import", js_code, "No Python syntax should appear")

        # Test 11: Ensure balanced syntax
        self.assert_balanced_syntax(js_code, fixture_path)

    def test_category2_default_imports_generate_correct_js(self) -> None:
        """Test Category 2 default imports from proposal document.

        Validates:
        - Default import: import from module { default as Name }
        - Generates: import Name from "module"
        - Works with relative paths

        Based on table from jac_import_patterns_proposal.md
        """
        fixture_path = self.get_fixture_path("category2_default_imports.jac")
        js_code = self.compile_fixture_to_js(fixture_path)

        # Test 1: Default import from react
        # cl import from react { default as React }
        # Should generate: import React from "react";
        self.assertIn(
            'import React from "react";',
            js_code,
            "Default import should generate: import React from 'react';"
        )

        # Test 2: Default import from axios
        self.assertIn(
            'import axios from "axios";',
            js_code,
            "Default import should generate: import axios from 'axios';"
        )

        # Test 3: Default import from vue
        self.assertIn(
            'import Vue from "vue";',
            js_code,
            "Default import should generate: import Vue from 'vue';"
        )

        # Test 4: Default import with relative path (single dot)
        self.assertIn(
            'import Button from "./components.Button";',
            js_code,
            "Relative default import should work with ./ path"
        )

        # Test 5: Default import with relative path (double dot)
        self.assertIn(
            'import utils from "../lib.utils";',
            js_code,
            "Relative default import should work with ../ path"
        )

        # Test 6: Ensure function definitions are generated
        self.assertIn(
            "function example_usage()",
            js_code,
            "Client function should be generated"
        )

        # Test 7: Verify no named import syntax leaked for defaults
        # Should NOT have: import { React } from "react"
        self.assertNotIn('import { React }', js_code, "Default should not use named import syntax")
        self.assertNotIn('import { axios }', js_code, "Default should not use named import syntax")
        self.assertNotIn('import { Vue }', js_code, "Default should not use named import syntax")

        # Test 8: Ensure balanced syntax
        self.assert_balanced_syntax(js_code, fixture_path)

    def test_category4_namespace_imports_generate_correct_js(self) -> None:
        """Test Category 4 namespace imports from proposal document.

        Validates:
        - Namespace import: import from module { * as Name }
        - Generates: import * as Name from "module"
        - Works with relative paths

        Based on table from jac_import_patterns_proposal.md
        """
        fixture_path = self.get_fixture_path("category4_namespace_imports.jac")
        js_code = self.compile_fixture_to_js(fixture_path)

        # Test 1: Namespace import from react
        # cl import from react { * as React }
        # Should generate: import * as React from "react";
        self.assertIn(
            'import * as React from "react";',
            js_code,
            "Namespace import should generate: import * as React from 'react';"
        )

        # Test 2: Namespace import from lodash
        self.assertIn(
            'import * as _ from "lodash";',
            js_code,
            "Namespace import should generate: import * as _ from 'lodash';"
        )

        # Test 3: Namespace import from dateutils
        self.assertIn(
            'import * as DateUtils from "dateutils";',
            js_code,
            "Namespace import should generate: import * as DateUtils from 'dateutils';"
        )

        # Test 4: Namespace import with relative path (single dot)
        self.assertIn(
            'import * as utils from "./utils";',
            js_code,
            "Relative namespace import should work with ./ path"
        )

        # Test 5: Namespace import with relative path (double dot)
        self.assertIn(
            'import * as helpers from "../lib.helpers";',
            js_code,
            "Relative namespace import should work with ../ path"
        )

        # Test 6: Ensure function definitions are generated
        self.assertIn(
            "function example_usage()",
            js_code,
            "Client function should be generated"
        )

        # Test 7: Verify no named import syntax leaked for namespace
        # Should NOT have: import { React } from "react"
        self.assertNotIn('import { * }', js_code, "Namespace should not use braces around *")
        self.assertNotIn('import { * as', js_code, "Namespace should not have * inside braces")

        # Test 8: Ensure balanced syntax
        self.assert_balanced_syntax(js_code, fixture_path)
