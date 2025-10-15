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
        self.assertIn('moduleFunctions["client_page"] = client_page;', bundle.code)
        self.assertIn('moduleFunctions["ButtonProps"] = ButtonProps;', bundle.code)
        self.assertIn('scope["client_page"] = client_page;', bundle.code)
        self.assertIn('scope["ButtonProps"] = ButtonProps;', bundle.code)
        self.assertIn('moduleGlobals["API_LABEL"] = API_LABEL;', bundle.code)
        self.assertIn('scope["API_LABEL"] = API_LABEL;', bundle.code)
        self.assertIn("hydrateJacClient", bundle.code)
        self.assertIn("document.getElementById('__jac_init__')", bundle.code)
        self.assertIn("Object.assign(scope, moduleGlobals);", bundle.code)
        self.assertIn("for (const [gName, gValue] of Object.entries(payload.globals", bundle.code)
        self.assertIn("client_page", bundle.client_functions)
        self.assertIn("ButtonProps", bundle.client_functions)
        self.assertIn("API_LABEL", bundle.client_globals)
        self.assertGreater(len(bundle.hash), 10)

        cached = builder.build(module)
        self.assertEqual(bundle.hash, cached.hash)
        self.assertEqual(bundle.code, cached.code)
