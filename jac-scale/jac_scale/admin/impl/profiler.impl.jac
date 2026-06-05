"""Yappi profiler admin endpoints — implementation."""
import io;
import logging;
import os;
import pstats;
import time;
import from pathlib { Path }
import from fastapi { Request }
import from fastapi.responses { JSONResponse }
import from jac_scale.jserver.jserver {
    HTTPMethod,
    JEndPoint,
    APIParameter,
    ParameterType
}

glob logger = logging.getLogger(__name__);


impl JacAPIServerProfiler.register_profiler_endpoints -> None {
    async def start_handler(request: Request) -> JSONResponse {
        auth_error = self.require_admin(request.headers.get("Authorization"));
        if auth_error {
            return JSONResponse(
                status_code=auth_error.meta.extra.get("http_status", 403),
                content={"ok": False, "error": {"message": "Unauthorized"}}
            );
        }
        try {
            import yappi;
        } except ImportError {
            return JSONResponse(
                status_code=500,
                content={
                    "ok": False,
                    "error": {
                        "message": "yappi is not installed. Run: pip install yappi"
                    }
                }
            );
        }
        if yappi.is_running() {
            return JSONResponse(
                content={
                    "ok": False,
                    "error": {"message": "Profiler is already running"}
                }
            );
        }
        body: dict = {};
        try {
            body = await request.json();
        } except Exception {
            body = {};
        }
        clock_type = body.get("clock_type", "wall");
        if clock_type not in ("wall", "cpu") {
            clock_type = "wall";
        }
        yappi.clear_stats();
        yappi.set_clock_type(clock_type);
        yappi.start();
        logger.info(f"Profiler started (clock_type={clock_type})");
        return JSONResponse(
            content={
                "ok": True,
                "data": {"message": "Profiler started", "clock_type": clock_type}
            }
        );
    }

    async def stop_handler(request: Request) -> JSONResponse {
        auth_error = self.require_admin(request.headers.get("Authorization"));
        if auth_error {
            return JSONResponse(
                status_code=auth_error.meta.extra.get("http_status", 403),
                content={"ok": False, "error": {"message": "Unauthorized"}}
            );
        }
        try {
            import yappi;
        } except ImportError {
            return JSONResponse(
                status_code=500,
                content={"ok": False, "error": {"message": "yappi is not installed"}}
            );
        }
        if not yappi.is_running() {
            return JSONResponse(
                content={"ok": False, "error": {"message": "Profiler is not running"}}
            );
        }
        yappi.stop();
        stats = yappi.get_func_stats();

        body: dict = {};
        try {
            body = await request.json();
        } except Exception {
            body = {};
        }
        output_dir = body.get("output_dir", os.environ.get("JAC_PROFILE_DIR", "."));
        Path(output_dir).mkdir(parents=True, exist_ok=True);
        ts = str(int(time.time()));
        prof_path = str(Path(output_dir) / f"profile_{ts}.prof");
        txt_path = str(Path(output_dir) / f"profile_{ts}.txt");

        # Save pstat-compatible .prof file
        stats.save(prof_path, type="pstat");

        # Save human-readable .txt file
        buf = io.StringIO();
        p = pstats.Stats(prof_path, stream=buf);
        p.sort_stats("cumulative");
        p.print_stats();
        Path(txt_path).write_text(buf.getvalue());

        # Build summary from top entries
        buf2 = io.StringIO();
        p2 = pstats.Stats(prof_path, stream=buf2);
        p2.sort_stats("cumulative");
        p2.print_stats(30);
        summary = buf2.getvalue();

        func_count = len(stats);
        yappi.clear_stats();
        logger.info(f"Profiler stopped. Saved {prof_path} and {txt_path}");
        return JSONResponse(
            content={
                "ok": True,
                "data": {
                    "message": "Profiler stopped",
                    "prof_file": prof_path,
                    "txt_file": txt_path,
                    "functions_profiled": func_count,
                    "summary": summary
                }
            }
        );
    }

    async def status_handler(request: Request) -> JSONResponse {
        auth_error = self.require_admin(request.headers.get("Authorization"));
        if auth_error {
            return JSONResponse(
                status_code=auth_error.meta.extra.get("http_status", 403),
                content={"ok": False, "error": {"message": "Unauthorized"}}
            );
        }
        try {
            import yappi;
        } except ImportError {
            return JSONResponse(
                content={"ok": True, "data": {"running": False, "available": False}}
            );
        }
        return JSONResponse(
            content={
                "ok": True,
                "data": {
                    "running": yappi.is_running(),
                    "available": True,
                    "clock_type": yappi.get_clock_type()
                }
            }
        );
    }

    self.server.add_endpoint(
        JEndPoint(
            method=HTTPMethod.POST,
            path="/admin/profiler/start",
            callback=start_handler,
            parameters=[],
            response_model=None,
            tags=["Profiler"],
            summary="Start yappi profiler",
            description="Start CPU/wall profiling. Pass {\"clock_type\": \"cpu\"} for CPU time, default is wall time."
        )
    );
    self.server.add_endpoint(
        JEndPoint(
            method=HTTPMethod.POST,
            path="/admin/profiler/stop",
            callback=stop_handler,
            parameters=[],
            response_model=None,
            tags=["Profiler"],
            summary="Stop profiler and save results",
            description="Stop profiling and save .prof + .txt files. Pass {\"output_dir\": \"path\"} to control output location (default: JAC_PROFILE_DIR or cwd)."
        )
    );
    self.server.add_endpoint(
        JEndPoint(
            method=HTTPMethod.GET,
            path="/admin/profiler/status",
            callback=status_handler,
            parameters=[],
            response_model=None,
            tags=["Profiler"],
            summary="Check profiler status",
            description="Check if yappi is installed and whether profiling is currently active."
        )
    );
}
