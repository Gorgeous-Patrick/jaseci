"""Vite-enhanced client bundle generation for Jac web front-ends."""

from __future__ import annotations

import contextlib
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from types import ModuleType
from typing import Any

from jaclang.runtimelib.client_bundle import (
    ClientBundle,
    ClientBundleBuilder,
    ClientBundleError,
)


class ViteClientBundleBuilder(ClientBundleBuilder):
    """Enhanced ClientBundleBuilder that uses Vite for optimized bundling."""

    def __init__(
        self,
        runtime_path: Path | None = None,
        vite_output_dir: Path | None = None,
        vite_package_json: Path | None = None,
        vite_minify: bool = False,
    ) -> None:
        """Initialize the Vite-enhanced bundle builder.

        Args:
            runtime_path: Path to client runtime file
            vite_output_dir: Output directory for Vite builds (defaults to temp/dist)
            vite_package_json: Path to package.json for Vite (required)
            vite_minify: Whether to enable minification in Vite build
        """
        super().__init__(runtime_path)
        self.vite_output_dir = vite_output_dir
        self.vite_package_json = vite_package_json
        self.vite_minify = vite_minify

    def _compile_bundle(
        self,
        module: ModuleType,
        module_path: Path,
    ) -> ClientBundle:
        """Override to use Vite bundling instead of simple concatenation."""
        # Get manifest from JacProgram first to check for imports
        from jaclang.runtimelib.machine import JacMachine as Jac

        mod = Jac.program.mod.hub.get(str(module_path))
        manifest = mod.gen.client_manifest if mod else None

        # Use base class method to process imports
        import_pieces, bundled_module_names = self._process_imports(
            manifest, module_path
        )

        # Compile main module and strip import statements for bundled modules
        module_js, _ = self._compile_to_js(module_path)
        module_js = self._strip_import_statements(module_js, bundled_module_names)

        # compile runtime to js and add to import_pieces
        runtime_js, _ = self._compile_to_js(self.runtime_path)
        import_pieces.append(f"// Imported runtime module: {self.runtime_path}")
        import_pieces.append(runtime_js)
        import_pieces.append("")

        # Use base class methods to extract exports and globals
        client_exports = self._extract_client_exports(manifest)
        client_globals_map = self._extract_client_globals(manifest, module)

        bundle_pieces = []

        # Add imported modules (which may include client_runtime if explicitly imported)
        if import_pieces:
            bundle_pieces.extend(import_pieces)

        # Add main module (without registration_js - we'll handle that in Jac init script)
        bundle_pieces.extend(
            [
                f"// Client module: {module.__name__}",
                module_js,
                "",
            ]
        )
        # Add global exposure code first (before Jac initialization)
        global_exposure_code = self._generate_global_exposure_code(client_exports)
        bundle_pieces.append(global_exposure_code)

        # Add Jac runtime initialization script (includes globals)
        jac_init_script = self._generate_jac_init_script(
            module.__name__, client_exports, client_globals_map
        )
        bundle_pieces.append(jac_init_script)

        # Use Vite bundling instead of simple concatenation
        bundle_code, bundle_hash = self._bundle_with_vite(
            bundle_pieces, module.__name__, client_exports
        )

        return ClientBundle(
            module_name=module.__name__,
            code=bundle_code,
            client_functions=client_exports,
            client_globals=list(client_globals_map.keys()),
            hash=bundle_hash,
        )

    def _bundle_with_vite(
        self, bundle_pieces: list[str], module_name: str, client_functions: list[str]
    ) -> tuple[str, str]:
        """Bundle JavaScript code using Vite for optimization.

        Args:
            bundle_pieces: List of JavaScript code pieces to bundle
            module_name: Name of the module being bundled
            client_functions: List of client function names

        Returns:
            Tuple of (bundle_code, bundle_hash)

        Raises:
            ClientBundleError: If Vite bundling fails
        """
        if not self.vite_package_json or not self.vite_package_json.exists():
            raise ClientBundleError(
                "Vite package.json not found. Set vite_package_json when using ViteClientBundleBuilder"
            )

        # Create temp directory for Vite build
        project_dir = self.vite_package_json.parent
        temp_dir = project_dir / "temp"
        temp_dir.mkdir(exist_ok=True)

        # Create entry file with stitched content
        entry_file = temp_dir / "main_entry.js"
        entry_content = "\n".join(piece for piece in bundle_pieces if piece is not None)
        entry_file.write_text(entry_content, encoding="utf-8")

        # Create Vite config in the project directory (where node_modules exists)
        vite_config = project_dir / "temp_vite.config.js"
        output_dir = self.vite_output_dir or temp_dir / "dist"
        output_dir.mkdir(exist_ok=True)

        config_content = self._generate_vite_config(entry_file, output_dir)
        vite_config.write_text(config_content, encoding="utf-8")

        try:
            # Run Vite build from project directory
            # need to install packages you told in package.json inside here
            command = ["npx", "vite", "build", "--config", str(vite_config)]
            subprocess.run(
                command, cwd=project_dir, check=True, capture_output=True, text=True
            )
        except subprocess.CalledProcessError as e:
            raise ClientBundleError(f"Vite build failed: {e.stderr}") from e
        except FileNotFoundError:
            raise ClientBundleError(
                "npx or vite command not found. Ensure Node.js and npm are installed."
            )
        finally:
            # Clean up temp config file
            if vite_config.exists():
                vite_config.unlink()

        # Find the generated bundle file
        bundle_file = self._find_vite_bundle(output_dir)
        if not bundle_file:
            raise ClientBundleError("Vite build completed but no bundle file found")

        # Read the bundled code
        bundle_code = bundle_file.read_text(encoding="utf-8")
        bundle_hash = hashlib.sha256(bundle_code.encode("utf-8")).hexdigest()

        return bundle_code, bundle_hash

    def _generate_vite_config(self, entry_file: Path, output_dir: Path) -> str:
        """Generate Vite configuration for bundling."""
        entry_name = entry_file.as_posix()
        output_dir_name = output_dir.as_posix()
        minify_setting = "true" if self.vite_minify else "false"

        return f"""
            import {{ defineConfig }} from 'vite';
            import {{ resolve }} from 'path';

            export default defineConfig({{
            build: {{
                outDir: '{output_dir_name}',
                emptyOutDir: true,
                rollupOptions: {{
                input: {{
                    main: resolve(__dirname, '{entry_name}'),
                }},
                output: {{
                    entryFileNames: 'client.[hash].js',
                    format: 'iife',
                    name: 'JacClient',
                }},
                }},
                minify: {minify_setting}, // Configurable minification
            }}
            }});
        """

    def _find_vite_bundle(self, output_dir: Path) -> Path | None:
        """Find the generated Vite bundle file."""
        for file in output_dir.glob("client.*.js"):
            return file
        return None

    def _generate_jac_init_script(
        self,
        module_name: str,
        client_functions: list[str],
        client_globals: dict[str, Any],
    ) -> str:
        """Generate Jac runtime initialization script."""
        if not client_functions:
            return ""

        # Generate function map dynamically
        map_entries = []
        for func_name in client_functions:
            map_entries.append(f'    "{func_name}": {func_name}')
        function_map_str = "{\n" + ",\n".join(map_entries) + "\n}"

        # Generate globals map
        globals_entries = []
        for name, value in client_globals.items():
            identifier = json.dumps(name)
            try:
                value_literal = json.dumps(value)
            except TypeError:
                value_literal = "null"
            globals_entries.append(f"{identifier}: {value_literal}")
        globals_literal = (
            "{ " + ", ".join(globals_entries) + " }" if globals_entries else "{}"
        )

        # Find the main app function (usually the last function or one ending with '_app')
        main_app_func = (
            "jac_app"  # this need to be always same and defined by our run time
        )
        # for func_name in reversed(client_functions):
        #     if func_name.endswith('_app') or func_name == 'App':
        #         main_app_func = func_name
        #         break

        return f"""
            // --- JAC CLIENT INITIALIZATION SCRIPT ---
            // Expose functions globally for Jac runtime registration
            const clientFunctions = {client_functions};
            const functionMap = {function_map_str};
            for (const funcName of clientFunctions) {{
                globalThis[funcName] = functionMap[funcName];
            }}
            __jacRegisterClientModule("{module_name}", clientFunctions, {globals_literal});
            globalThis.start_app = {main_app_func};
            // Call the start function immediately if we're not hydrating from the server
            if (!document.getElementById('__jac_init__')) {{
                globalThis.start_app();
            }}
            // --- END JAC CLIENT INITIALIZATION SCRIPT ---
        """

    def _generate_global_exposure_code(self, client_functions: list[str]) -> str:
        """Generate code to expose functions globally for Vite IIFE."""
        if not client_functions:
            return ""

        # Generate function map dynamically
        map_entries = []
        for func_name in client_functions:
            map_entries.append(f'    "{func_name}": {func_name}')
        function_map_str = "{\n" + ",\n".join(map_entries) + "\n}"

        return f"""
            // --- GLOBAL EXPOSURE FOR VITE IIFE ---
            // Expose functions globally so they're available on globalThis
            const globalClientFunctions = {client_functions};
            const globalFunctionMap = {function_map_str};
            for (const funcName of globalClientFunctions) {{
                globalThis[funcName] = globalFunctionMap[funcName];
            }}
            // --- END GLOBAL EXPOSURE ---
        """

    def cleanup_temp_dir(self) -> None:
        """Clean up the temp directory and its contents."""
        if not self.vite_package_json or not self.vite_package_json.exists():
            return

        project_dir = self.vite_package_json.parent
        temp_dir = project_dir / "temp"

        if temp_dir.exists():
            with contextlib.suppress(OSError):
                shutil.rmtree(temp_dir)
