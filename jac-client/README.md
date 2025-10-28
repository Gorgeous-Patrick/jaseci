Jac Client
==========

Lightweight plugin that adds Vite-powered client bundling to Jac programs. It provides a `ClientBundleBuilder` implementation discovered by the Jac runtime via entry-points, so you can generate optimized browser bundles from Jac client code automatically.

Requirements
------------
- Python: 3.12+
- Python deps: `jaclang==0.8.10` (installed transitively)
- Node.js tooling available on PATH:
  - `node`/`npm` (or `pnpm`/`yarn` if `npx` can execute Vite)
  - `npx` and Vite present in your frontend project (`devDependencies`)

Install
-------
Using pip:

```bash
pip install jac-client
```

Using Poetry inside a project:

```bash
poetry add jac-client
```

```
your_app/
  package.json           # contains vite in devDependencies
  node_modules/
  static/
    client/
      js/                # Vite output will be written here
  your_program.jac       # your Jac source
```

How it works
------------
At runtime, Jac discovers the `JacClient` plugin and calls its builder:

- `jac_client.plugin.client.JacClient.get_client_bundle_builder()` returns `ViteClientBundleBuilder` configured with paths resolved from `JacMachine.base_path_dir`.
- The builder compiles `.jac` client code to JS, stitches any client imports, injects an init script that registers exports with the Jac runtime, then runs Vite to produce an optimized IIFE bundle named `client.[hash].js`.

Troubleshooting
---------------
- npx/vite not found: ensure Node.js is installed and that `package.json` has Vite in `devDependencies` (so `npx vite` works in your app root).
- Build completes but no bundle found: the builder expects Vite to emit `client.[hash].js`; check custom Vite configs or permissions in the output directory.
- Output directory missing: the plugin will create the directory if needed, but verify the process has write permissions to `<base_path_dir>/static/client/js`.

Contributing
------------
- See `jac-client/TODO.md` for improvements and `jac-client/ROADMAP.md` for direction.
- PRs to enhance cross-platform path handling, dev HMR, and caching are welcome.

License
-------
MIT (see repository root `LICENSE`).


