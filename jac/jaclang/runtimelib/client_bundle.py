"""Client bundle generation utilities for Jac web front-ends."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any, Iterable, Sequence

from jaclang.compiler.program import JacProgram


class ClientBundleError(RuntimeError):
    """Raised when the client bundle cannot be generated."""


@dataclass(slots=True)
class ClientBundle:
    """Container for a compiled client bundle."""

    module_name: str
    code: str
    client_functions: list[str]
    client_globals: list[str]
    hash: str


@dataclass(slots=True)
class _CachedBundle:
    signature: str
    bundle: ClientBundle


class ClientBundleBuilder:
    """Compile Jac modules and runtime support into a browser-ready bundle."""

    def __init__(self, runtime_path: Path | None = None) -> None:
        """Initialise the builder with an optional override for the runtime path."""
        self.runtime_path = runtime_path or Path(__file__).with_name(
            "client_runtime.jac"
        )
        self._cache: dict[str, _CachedBundle] = {}

    def build(self, module: ModuleType, force: bool = False) -> ClientBundle:
        """Build (or reuse) a client bundle for the supplied module."""
        # Derive source path from module __file__ (replace .py with .jac)
        if not hasattr(module, "__file__") or not module.__file__:
            raise ClientBundleError(
                f"Module '{module.__name__}' has no __file__ attribute"
            )
        module_path = module.__file__.replace(".py", ".jac")

        source_path = Path(module_path).resolve()
        runtime_path = self.runtime_path.resolve()
        signature = self._signature([source_path, runtime_path])

        cached = self._cache.get(module.__name__)
        if not force and cached and cached.signature == signature:
            return cached.bundle

        bundle = self._compile_bundle(module, source_path, runtime_path)
        self._cache[module.__name__] = _CachedBundle(signature=signature, bundle=bundle)
        return bundle

    def _compile_bundle(
        self,
        module: ModuleType,
        module_path: Path,
        runtime_path: Path,
    ) -> ClientBundle:
        """Compile bundle pieces and stitch them together."""
        runtime_js = self._compile_to_js(runtime_path)

        # Get manifest from JacProgram instead of module attribute
        from jaclang.runtimelib.machine import JacMachine as Jac

        manifest = Jac.program.get_client_manifest(str(module_path)) or {}
        manifest_exports = manifest.get("exports", [])
        manifest_globals = manifest.get("globals", [])
        manifest_globals_values = manifest.get("globals_values", {})
        module_js = self._compile_to_js(module_path)

        client_exports = list(manifest_exports)

        client_globals_list = list(manifest_globals) if manifest_globals else []

        client_globals_map: dict[str, Any] = {}
        for name in client_globals_list:
            if name in manifest_globals_values:
                client_globals_map[name] = manifest_globals_values[name]
            elif hasattr(module, name):
                client_globals_map[name] = getattr(module, name)
            else:
                client_globals_map[name] = None

        client_exports = sorted(dict.fromkeys(client_exports))
        client_globals_map = {
            key: client_globals_map[key] for key in sorted(client_globals_map)
        }

        registration_js = self._generate_registration_js(
            module.__name__, client_exports, client_globals_map
        )

        # Add Object.prototype.get polyfill for Python dict-like behavior
        polyfill_js = (
            "// Polyfill: Add .get() method to objects for Python dict-like behavior\n"
            "if (!Object.prototype.get) {\n"
            "  Object.prototype.get = function(key, defaultValue) {\n"
            "    return this.hasOwnProperty(key) ? this[key] : (defaultValue !== undefined ? defaultValue : null);\n"
            "  };\n"
            "}\n"
        )

        bundle_pieces = [
            polyfill_js,
            "// Jac client runtime",
            runtime_js,
            "",
            f"// Client module: {module.__name__}",
            module_js,
            "",
            registration_js,
        ]
        bundle_code = "\n".join(piece for piece in bundle_pieces if piece is not None)
        bundle_hash = hashlib.sha256(bundle_code.encode("utf-8")).hexdigest()

        return ClientBundle(
            module_name=module.__name__,
            code=bundle_code,
            client_functions=client_exports,
            client_globals=list(client_globals_map.keys()),
            hash=bundle_hash,
        )

    def _compile_to_js(self, source_path: Path) -> str:
        """Compile the provided Jac file into JavaScript."""
        program = JacProgram()
        mod = program.compile(str(source_path))
        if program.errors_had:
            formatted = "\n".join(str(err) for err in program.errors_had)
            raise ClientBundleError(
                f"Failed to compile '{source_path}' for client bundle:\n{formatted}"
            )
        return mod.gen.js or ""

    @staticmethod
    def _signature(paths: Iterable[Path]) -> str:
        """Compute a cache signature based on file modification times."""
        parts: list[str] = []
        for path in paths:
            try:
                stat = path.stat()
                parts.append(f"{path}:{stat.st_mtime_ns}")
            except FileNotFoundError:
                parts.append(f"{path}:missing")
        return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()

    @staticmethod
    def _generate_registration_js(
        module_name: str,
        client_functions: Sequence[str],
        client_globals: dict[str, Any],
    ) -> str:
        """Generate registration code that exposes client symbols globally."""
        lines: list[str] = [
            "(function registerJacClientModule(){",
            "  const scope = typeof globalThis !== 'undefined' ? globalThis : window;",
            "  const registry = scope.__jacClient || (scope.__jacClient ="
            " { functions: {}, globals: {}, modules: {} });",
            "  const moduleFunctions = {};",
            "  const moduleGlobals = {};",
        ]

        for name in client_functions:
            lines.append(f"  moduleFunctions[{json.dumps(name)}] = {name};")
            lines.append(f"  scope[{json.dumps(name)}] = {name};")
        for name, value in client_globals.items():
            identifier = json.dumps(name)
            try:
                value_literal = json.dumps(value)
            except TypeError:
                value_literal = "null"
            lines.append(f"  if (typeof {name} !== 'undefined') {{")
            lines.append(f"    moduleGlobals[{identifier}] = {name};")
            lines.append(f"    scope[{identifier}] = {name};")
            lines.append("  } else {")
            lines.append(f"    moduleGlobals[{identifier}] = {value_literal};")
            lines.append(f"    scope[{identifier}] = {value_literal};")
            lines.append("  }")

        lines.append(f"  registry.modules[{json.dumps(module_name)}] = {{")
        lines.append(f"    functions: {json.dumps(list(client_functions))},")
        lines.append(f"    globals: {json.dumps(list(client_globals.keys()))}")
        lines.append("  };")
        lines.append("  registry.state = registry.state || {};")
        lines.append("  registry.state.globals = registry.state.globals || {};")
        lines.append("  Object.assign(registry.functions, moduleFunctions);")
        lines.append("  Object.assign(registry.globals, moduleGlobals);")
        lines.append("  Object.assign(scope, moduleGlobals);")
        lines.append("  function hydrateJacClient(){")
        lines.append("    if (typeof document === 'undefined') { return; }")
        lines.append("    const initEl = document.getElementById('__jac_init__');")
        lines.append("    const rootEl = document.getElementById('__jac_root');")
        lines.append(
            "    if (!initEl || !rootEl || initEl.dataset.jacHydrated === 'true') { return; }"
        )
        lines.append("    initEl.dataset.jacHydrated = 'true';")
        lines.append("    let payload;")
        lines.append("    try {")
        lines.append("      payload = JSON.parse(initEl.textContent || '{}');")
        lines.append("    } catch (err) {")
        lines.append(
            "      console.error('[Jac] Failed to parse hydration payload', err);"
        )
        lines.append("      return;")
        lines.append("    }")
        lines.append("    if (!payload || !payload.function) { return; }")
        lines.append(
            f"    const moduleName = payload.module || {json.dumps(module_name)};"
        )
        lines.append(
            "    const argsOrder = Array.isArray(payload.argOrder) ? payload.argOrder : [];"
        )
        lines.append("    const argsDict = payload.args || {};")
        lines.append("    const orderedArgs = argsOrder.map((name) => argsDict[name]);")
        lines.append("    const targetName = payload.function;")
        lines.append(
            "    const target = moduleFunctions[targetName] || registry.functions[targetName];"
        )
        lines.append("    if (typeof target !== 'function') {")
        lines.append(
            "      console.error('[Jac] Client function not found:', targetName);"
        )
        lines.append("      return;")
        lines.append("    }")
        lines.append("    registry.state.globals[moduleName] = payload.globals || {};")
        lines.append(
            "    for (const [gName, gValue] of Object.entries(payload.globals || {})) {"
        )
        lines.append("      scope[gName] = gValue;")
        lines.append("    }")
        lines.append("    const applyRender = (node) => {")
        lines.append(
            "      const renderer = scope.renderJsxTree || "
            "(typeof renderJsxTree === 'function' ? renderJsxTree : null);"
        )
        lines.append("      if (!renderer) {")
        lines.append(
            "        console.warn('[Jac] renderJsxTree is not available in client bundle');"
        )
        lines.append("        return;")
        lines.append("      }")
        lines.append("      try {")
        lines.append("        renderer(node, rootEl);")
        lines.append("      } catch (err) {")
        lines.append("        console.error('[Jac] Failed to render JSX tree', err);")
        lines.append("      }")
        lines.append("    };")
        lines.append("    let result;")
        lines.append("    try {")
        lines.append("      result = target.apply(scope, orderedArgs);")
        lines.append("    } catch (err) {")
        lines.append(
            "      console.error('[Jac] Error executing client function', targetName, err);"
        )
        lines.append("      return;")
        lines.append("    }")
        lines.append("    if (result && typeof result.then === 'function') {")
        lines.append("      result.then(applyRender).catch((err) => {")
        lines.append(
            "        console.error('[Jac] Error resolving client function promise', err);"
        )
        lines.append("      });")
        lines.append("    } else {")
        lines.append("      applyRender(result);")
        lines.append("    }")
        lines.append("  }")
        lines.append("  if (typeof document !== 'undefined') {")
        lines.append("    if (document.readyState === 'loading') {")
        lines.append(
            "      document.addEventListener('DOMContentLoaded', hydrateJacClient, { once: true });"
        )
        lines.append("    } else {")
        lines.append("      hydrateJacClient();")
        lines.append("    }")
        lines.append("  }")
        lines.append("})();")
        return "\n".join(lines)
