"""Implementation of the Jac-native desktop target."""
import os;
import shutil;
import json;
import subprocess;
import sysconfig;
import from pathlib { Path }
import from typing { Optional }
import from jaclang.cli.console { console }

"""Locate the shipped native/webview assets (binding + build tooling).

native/webview lives inside this package, two dirs up from this targets module
(jac_desktop/targets/ -> jac_desktop/native/webview). Verified by the presence
of webview.na.jac; walks up as a fallback for unusual layouts.
"""
def _find_webview_dir -> Path {
    here = Path(os.path.abspath(__file__)).parent;
    candidates = [here.parent / "native" / "webview", here / "native" / "webview"];
    p = here;
    for _ in range(6) {
        candidates.append(p / "native" / "webview");
        p = p.parent;
    }
    for cand in candidates {
        if (cand / "webview.na.jac").exists() {
            return cand;
        }
    }
    raise RuntimeError("jac-desktop: native/webview assets not found in the package.");
}

"""Resolve the jac CLI for nacompile (we're running under it)."""
def _jac_bin -> str {
    found = shutil.which("jac");
    if found {
        return found;
    }
    cand = Path(os.path.dirname(os.sys.executable)) / "jac";
    if cand.exists() {
        return str(cand);
    }
    raise RuntimeError("jac CLI not found on PATH.");
}

"""Ensure libwebview.so exists beside the binding (build it on first use)."""
def _ensure_libwebview(webview_dir: Path) -> Path {
    lib = webview_dir / "libwebview.so";
    if lib.exists() {
        return lib;
    }
    console.print("  Building libwebview.so (one-time)...", style="muted");
    res = subprocess.run([str(webview_dir / "build_libwebview.sh")]);
    if res.returncode != 0 or not lib.exists() {
        raise RuntimeError(
            "Failed to build libwebview.so - is WebKitGTK + a C toolchain installed? "
            "See jac_desktop/native/webview/README.md."
        );
    }
    return lib;
}

"""Generate the native host source: embed CPython, serve `dist/` (resolved next
to the binary via /proc/self/exe) on loopback, render it in the webview."""
def _generate_host_source(libpy: str, title: str, width: int, height: int) -> str {
    serve_py = (
        "import os, http.server, socketserver, threading, functools\n"
        "_exe = os.path.realpath('/proc/self/exe')\n"
        "_dir = os.path.join(os.path.dirname(_exe), 'dist')\n"
        "_H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=_dir)\n"
        "_srv = socketserver.TCPServer(('127.0.0.1', 0), _H)\n"
        "_port = _srv.server_address[1]\n"
        "threading.Thread(target=_srv.serve_forever, daemon=True).start()\n"
    );
    return (
        '"""Generated native desktop host - do not edit (jac-desktop)."""\n'
        "import from webview { Webview, new_webview, HINT_NONE }\n"
        f'import from "{libpy}" {{\n'
        "    def Py_Initialize() -> None;\n"
        "    def Py_Finalize() -> None;\n"
        "    def PyRun_SimpleString(cmd: str) -> i32;\n"
        "    def PyImport_AddModule(name: str) -> int;\n"
        "    def PyModule_GetDict(module: int) -> int;\n"
        "    def PyRun_String(s: str, start: i32, g: int, l: int) -> int;\n"
        "    def PyLong_AsLong(o: int) -> int;\n"
        "    def PyEval_SaveThread() -> int;\n"
        "    def PyEval_RestoreThread(s: int) -> None;\n"
        "}\n"
        "glob PY_EVAL: i32 = 258;\n"
        f"glob SERVE_PY: str = {json.dumps(serve_py, ensure_ascii=False)};\n"
        "with entry {\n"
        "    Py_Initialize();\n"
        "    PyRun_SimpleString(SERVE_PY);\n"
        "    main_mod = PyImport_AddModule(\"__main__\");\n"
        "    d = PyModule_GetDict(main_mod);\n"
        "    port = PyLong_AsLong(PyRun_String(\"_port\", PY_EVAL, d, d));\n"
        "    url = f\"http://127.0.0.1:{port}/\";\n"
        "    wv = new_webview(False);\n"
        f"    wv.title({json.dumps(title, ensure_ascii=False)});\n"
        f"    wv.size({width}, {height}, HINT_NONE);\n"
        "    wv.navigate(url);\n"
        "    ts = PyEval_SaveThread();\n"
        "    wv.run();\n"
        "    PyEval_RestoreThread(ts);\n"
        "    Py_Finalize();\n"
        "}\n"
    );
}

impl NativeDesktopTarget.setup(project_dir: Path) -> None { }

impl NativeDesktopTarget.build(
    entry_file: Path, project_dir: Path, platform: Optional[str] = None
) -> Path {
    import from jac_desktop.config_loader { get_desktop_config }

    # 1. Build the cl bundle with the standard Vite pipeline (WebTarget).
    console.print("\n🖥️  Building desktop app (Jac-native webview)", style="bold");
    web_bundle = super.build(entry_file, project_dir, platform);
    dist_dir = web_bundle.parent;  # .jac/client/dist

    # 2. Desktop window config from [plugins.desktop].
    cfg = get_desktop_config(project_dir);
    ident = cfg.get_identity();
    win = cfg.get_window_config();
    app_name = ident.name or "app";

    # 3. Prepare a clean output dir beside the dist.
    out_dir = project_dir / self.output_dir;
    if out_dir.exists() {
        shutil.rmtree(out_dir);
    }
    out_dir.mkdir(parents=True, exist_ok=True);

    # 4. Stage the served bundle + the native engine wrapper.
    shutil.copytree(dist_dir, out_dir / "dist");
    webview_dir = _find_webview_dir();
    lib = _ensure_libwebview(webview_dir);
    shutil.copy2(lib, out_dir / "libwebview.so");
    shutil.copy2(webview_dir / "webview.na.jac", out_dir / "webview.na.jac");

    # 5. Generate + compile the native host into the output dir.
    libpy = sysconfig.get_config_var("INSTSONAME") or "libpython3.12.so.1.0";
    host_src = _generate_host_source(
        libpy, win.title or app_name, win.width, win.height
    );
    (out_dir / "host.na.jac").write_text(host_src);

    console.print("  Compiling native host (jac nacompile)...", style="muted");
    res = subprocess.run(
        [_jac_bin(), "nacompile", "host.na.jac", "-o", app_name], cwd=str(out_dir)
    );
    if res.returncode != 0 {
        raise RuntimeError("Native host compilation failed.");
    }
    binary = out_dir / app_name;
    console.print(f"\n✅ Desktop app built: {binary}", style="bold green");
    console.print(f"   run: (cd {out_dir} && ./{app_name})", style="muted");
    return binary;
}

impl NativeDesktopTarget.start(
    entry_file: Path, project_dir: Path, api_port: int = 8000
) -> None {
    binary = self.build(entry_file, project_dir, None);
    env = dict(os.environ);
    # WebKitGTK on WSL/headless-ish setups: prefer X11 + software paths.
    env.setdefault("GDK_BACKEND", "x11");
    env.setdefault("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    env.setdefault("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
    console.print(f"\n🚀 Launching {binary.name}", style="bold green");
    try {
        subprocess.run([str(binary)], cwd=str(binary.parent), env=env);
    } except KeyboardInterrupt {
        console.print("\n  Closing desktop app...", style="muted");
    }
}

impl NativeDesktopTarget.dev(
    entry_file: Path, project_dir: Path, port: int = 8000, api_port: int = 0
) -> None {
    # MVP: build + run (no HMR yet). HMR dev (native window -> Vite dev server)
    # is a follow-up.
    console.print(
        "  desktop --dev: building and launching (HMR not yet wired)", style="muted"
    );
    self.start(entry_file, project_dir, api_port);
}
