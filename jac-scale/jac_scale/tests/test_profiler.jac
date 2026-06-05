"""Tests for the yappi profiler admin endpoints.

Registration tests verify endpoint paths, methods, and tags.
Functional tests exercise the start/stop/status handlers directly
using a mock admin host and asyncio.
"""

import asyncio;
import json;
import os;
import shutil;
import tempfile;
import from pathlib { Path }
import from unittest.mock { MagicMock }
import from jac_scale.admin.profiler { JacAPIServerProfiler }
import from jac_scale.jserver.jfast_api { JFastApiServer }
import from jac_scale.jserver.jserver { HTTPMethod }


"""Minimal host with the profiler mixin and a stub require_admin."""
obj ProfilerHost(JacAPIServerProfiler) {
    has server: any = None;

    """Always allow — returns None (no auth error)."""
    def require_admin(Authorization: str | None) -> any {
        return None;
    }
}


"""Build a fake Request whose .json() returns `body` and .headers works."""
def _fake_request(body: dict | None = None) -> any {
    req = MagicMock();
    req.headers = MagicMock();
    req.headers.get = MagicMock(return_value="Bearer fake-admin-token");

    async def json_coro -> dict {
        return body if body is not None else {};
    }
    req.json = json_coro;
    return req;
}


# --- Registration tests -----------------------------------------------------
test "register_profiler_endpoints adds 3 endpoints" {
    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    paths = [e.path for e in host.server._endpoints];
    assert "/admin/profiler/start" in paths;
    assert "/admin/profiler/stop" in paths;
    assert "/admin/profiler/status" in paths;
}


test "start and stop are POST, status is GET" {
    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    method_map: dict[str, any] = {};
    for ep in host.server._endpoints {
        if ep.path.startswith("/admin/profiler") {
            method_map[ep.path] = ep.method;
        }
    }
    assert method_map["/admin/profiler/start"] == HTTPMethod.POST;
    assert method_map["/admin/profiler/stop"] == HTTPMethod.POST;
    assert method_map["/admin/profiler/status"] == HTTPMethod.GET;
}


test "all profiler endpoints are tagged Profiler" {
    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    for ep in host.server._endpoints {
        if ep.path.startswith("/admin/profiler") {
            assert ep.tags == ["Profiler"] , (
                f"{ep.path} should be tagged ['Profiler'], got {ep.tags}"
            );
        }
    }
}


# --- Functional tests (require yappi) ----------------------------------------
test "status reports available and not running initially" {
    try {
        import yappi;
    } except ImportError {
        return;
    }
    # Ensure clean state
    if yappi.is_running() {
        yappi.stop();
    }
    yappi.clear_stats();

    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    handler = None;
    for ep in host.server._endpoints {
        if ep.path == "/admin/profiler/status" {
            handler = ep.callback;
        }
    }
    assert handler is not None;

    resp = asyncio.run(handler(_fake_request()));
    data = json.loads(resp.body);
    assert data["ok"] is True;
    assert data["data"]["available"] is True;
    assert data["data"]["running"] is False;
}


test "start then status shows running" {
    try {
        import yappi;
    } except ImportError {
        return;
    }
    if yappi.is_running() {
        yappi.stop();
    }
    yappi.clear_stats();

    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    handlers: dict[str, any] = {};
    for ep in host.server._endpoints {
        if ep.path.startswith("/admin/profiler") {
            handlers[ep.path] = ep.callback;
        }
    }

    # Start
    resp = asyncio.run(handlers["/admin/profiler/start"](_fake_request()));
    data = json.loads(resp.body);
    assert data["ok"] is True;
    assert data["data"]["clock_type"] == "wall";

    # Status should show running
    resp = asyncio.run(handlers["/admin/profiler/status"](_fake_request()));
    data = json.loads(resp.body);
    assert data["data"]["running"] is True;

    # Cleanup
    yappi.stop();
    yappi.clear_stats();
}


test "start while already running returns error" {
    try {
        import yappi;
    } except ImportError {
        return;
    }
    if yappi.is_running() {
        yappi.stop();
    }
    yappi.clear_stats();

    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    start_handler = None;
    for ep in host.server._endpoints {
        if ep.path == "/admin/profiler/start" {
            start_handler = ep.callback;
        }
    }

    # First start succeeds
    asyncio.run(start_handler(_fake_request()));
    assert yappi.is_running();

    # Second start should fail
    resp = asyncio.run(start_handler(_fake_request()));
    data = json.loads(resp.body);
    assert data["ok"] is False;
    assert "already running" in data["error"]["message"];

    # Cleanup
    yappi.stop();
    yappi.clear_stats();
}


test "stop without start returns error" {
    try {
        import yappi;
    } except ImportError {
        return;
    }
    if yappi.is_running() {
        yappi.stop();
    }
    yappi.clear_stats();

    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    stop_handler = None;
    for ep in host.server._endpoints {
        if ep.path == "/admin/profiler/stop" {
            stop_handler = ep.callback;
        }
    }

    resp = asyncio.run(stop_handler(_fake_request()));
    data = json.loads(resp.body);
    assert data["ok"] is False;
    assert "not running" in data["error"]["message"];
}


test "full start-stop cycle produces .prof and .txt files" {
    try {
        import yappi;
    } except ImportError {
        return;
    }
    if yappi.is_running() {
        yappi.stop();
    }
    yappi.clear_stats();

    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    handlers: dict[str, any] = {};
    for ep in host.server._endpoints {
        if ep.path.startswith("/admin/profiler") {
            handlers[ep.path] = ep.callback;
        }
    }

    tmpdir = tempfile.mkdtemp();

    try {
        # Start
        asyncio.run(handlers["/admin/profiler/start"](_fake_request()));

        # Do some work so yappi has something to profile
        total = sum(range(1000));

        # Stop with custom output_dir
        resp = asyncio.run(
            handlers["/admin/profiler/stop"](_fake_request({"output_dir": tmpdir}))
        );
        data = json.loads(resp.body);
        assert data["ok"] is True;
        assert data["data"]["functions_profiled"] > 0;

        # Verify files exist
        prof_path = data["data"]["prof_file"];
        txt_path = data["data"]["txt_file"];
        assert Path(prof_path).exists() , f".prof file not found: {prof_path}";
        assert Path(txt_path).exists() , f".txt file not found: {txt_path}";
        assert Path(txt_path).stat().st_size > 0 , ".txt file is empty";

        # Summary should contain function stats
        assert "function calls" in data["data"]["summary"];

        # Status should show not running
        resp = asyncio.run(handlers["/admin/profiler/status"](_fake_request()));
        data = json.loads(resp.body);
        assert data["data"]["running"] is False;
    } finally {
        if yappi.is_running() {
            yappi.stop();
        }
        yappi.clear_stats();
        shutil.rmtree(tmpdir, ignore_errors=True);
    }
}


test "start with cpu clock_type is accepted" {
    try {
        import yappi;
    } except ImportError {
        return;
    }
    if yappi.is_running() {
        yappi.stop();
    }
    yappi.clear_stats();

    host = ProfilerHost();
    host.server = JFastApiServer();
    host.register_profiler_endpoints();

    start_handler = None;
    for ep in host.server._endpoints {
        if ep.path == "/admin/profiler/start" {
            start_handler = ep.callback;
        }
    }

    resp = asyncio.run(start_handler(_fake_request({"clock_type": "cpu"})));
    data = json.loads(resp.body);
    assert data["ok"] is True;
    assert data["data"]["clock_type"] == "cpu";

    yappi.stop();
    yappi.clear_stats();
}
