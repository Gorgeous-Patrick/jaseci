"""Tests for client bundle generation."""

from __future__ import annotations

from pathlib import Path

from jaclang.runtimelib.client_bundle import ClientBundleBuilder
from jaclang.runtimelib.machine import JacMachine as Jac
from jaclang.utils.test import TestCase


class ClientBundleBuilderTests(TestCase):
    """Validate client bundle compilation."""

    def setUp(self) -> None:
        Jac.reset_machine()
        return super().setUp()

    def tearDown(self) -> None:
        Jac.reset_machine()
        return super().tearDown()

    def test_build_bundle_for_module(self) -> None:
        """Compile a Jac module and ensure client bundle metadata is emitted."""
        fixtures_dir = Path(__file__).parent / "fixtures"
        (module,) = Jac.jac_import("client_app", str(fixtures_dir))

        builder = ClientBundleBuilder()
        bundle = builder.build(module)

        self.assertIn("function __jacJsx", bundle.code)
        # Check that registration mechanism is present
        self.assertIn('moduleFunctions[funcName] = funcRef;', bundle.code)
        self.assertIn('scope[funcName] = funcRef;', bundle.code)
        self.assertIn('moduleGlobals[gName] = existing;', bundle.code)
        self.assertIn('scope[gName] = defaultValue;', bundle.code)
        # Check that actual client functions and globals are defined
        self.assertIn('function client_page()', bundle.code)
        self.assertIn('class ButtonProps', bundle.code)
        self.assertIn('const API_LABEL = "Runtime Test";', bundle.code)
        # Check hydration logic is present
        self.assertIn("__jacHydrateFromDom", bundle.code)
        self.assertIn("__jacEnsureHydration", bundle.code)
        self.assertIn('getElementById("__jac_init__")', bundle.code)
        self.assertIn('getElementById("__jac_root")', bundle.code)
        # Check globals iteration logic
        self.assertIn("for (const gName of __objectKeys(payloadGlobals))", bundle.code)
        self.assertIn("client_page", bundle.client_functions)
        self.assertIn("ButtonProps", bundle.client_functions)
        self.assertIn("API_LABEL", bundle.client_globals)
        self.assertGreater(len(bundle.hash), 10)

        cached = builder.build(module)
        self.assertEqual(bundle.hash, cached.hash)
        self.assertEqual(bundle.code, cached.code)

    def test_build_bundle_with_cl_import(self) -> None:
        """Test that cl import statements are properly bundled."""
        fixtures_dir = Path(__file__).parent / "fixtures"
        (module,) = Jac.jac_import("client_app_with_import", str(fixtures_dir))

        builder = ClientBundleBuilder()
        bundle = builder.build(module)

        # Check that client_runtime functions are included in the bundle
        self.assertIn("function renderJsxTree", bundle.code)
        self.assertIn("function jacLogin", bundle.code)

        # Check that our client code is present
        self.assertIn("function test_page()", bundle.code)
        self.assertIn('const APP_TITLE = "Import Test App";', bundle.code)

        # Verify the imported module comment is present
        self.assertIn("// Imported .jac module: client_runtime", bundle.code)

        # IMPORTANT: Ensure no ES6 import statements are in the bundle
        # (since everything is bundled together, we don't need module imports)
        self.assertNotIn("import {", bundle.code)
        self.assertNotIn("from \"client_runtime\"", bundle.code)

        # Check that client functions are registered
        self.assertIn("test_page", bundle.client_functions)
        self.assertIn("APP_TITLE", bundle.client_globals)

        # Ensure the bundle has a valid hash
        self.assertGreater(len(bundle.hash), 10)
