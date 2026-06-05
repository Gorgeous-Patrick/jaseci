"""Yappi-based profiler admin endpoints.

Provides start/stop/status endpoints for on-demand CPU profiling of the
running Jac server. Results are saved as both .prof (pstat-compatible)
and .txt (human-readable sorted stats) files.

Endpoints (all admin-auth-gated):
  POST /admin/profiler/start   - start profiling (clock_type: wall|cpu)
  POST /admin/profiler/stop    - stop profiling, save results, return summary
  GET  /admin/profiler/status  - check if profiler is running
"""
import from collections.abc { Callable }
import from fastapi { Request }
import from fastapi.responses { JSONResponse }
import from jaclang.runtimelib.transport { TransportResponse }
import from jac_scale.jserver.jserver {
    HTTPMethod,
    JEndPoint,
    APIParameter,
    ParameterType
}

"""Mixin providing yappi profiler admin endpoints."""
obj JacAPIServerProfiler {
    def register_profiler_endpoints -> None;
}
