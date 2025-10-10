"""Test for jac serve command and REST API server."""

import json
import os
import socket
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jaclang.cli import cli
from jaclang.runtimelib.machine import JacMachine as Jac
from jaclang.runtimelib.server import JacAPIServer, UserManager
from jaclang.utils.test import TestCase


def get_free_port() -> int:
    """Get a free port by binding to port 0 and releasing it."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.listen(1)
        port = s.getsockname()[1]
    return port


class TestServeCommand(TestCase):
    """Test jac serve REST API functionality."""

    def setUp(self) -> None:
        """Set up test."""
        super().setUp()
        self.server = None
        self.server_thread = None
        self.httpd = None
        # Use dynamically allocated free port for each test
        self.port = get_free_port()
        self.base_url = f"http://localhost:{self.port}"
        # Use unique session file for each test
        test_name = self._testMethodName
        self.session_file = self.fixture_abs_path(f"test_serve_{test_name}.session")

    def tearDown(self) -> None:
        """Tear down test."""
        # Stop server if running
        if self.httpd:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
            except Exception:
                pass

        # Wait for thread to finish
        if self.server_thread and self.server_thread.is_alive():
            self.server_thread.join(timeout=2)

        # Clean up session files
        self._del_session(self.session_file)
        super().tearDown()

    def _del_session(self, session: str) -> None:
        """Delete session files."""
        path = os.path.dirname(session)
        prefix = os.path.basename(session)
        if os.path.exists(path):
            for file in os.listdir(path):
                if file.startswith(prefix):
                    try:
                        os.remove(f"{path}/{file}")
                    except Exception:
                        pass

    def _start_server(self) -> None:
        """Start the API server in a background thread."""
        from http.server import HTTPServer

        # Load the module
        base, mod, mach = cli.proc_file_sess(
            self.fixture_abs_path("serve_api.jac"), ""
        )
        Jac.set_base_path(base)
        Jac.jac_import(
            target=mod,
            base_path=base,
            override_name="__main__",
            lng="jac",
        )

        # Create server
        self.server = JacAPIServer(
            module_name="__main__",
            session_path=self.session_file,
            port=self.port,
        )

        # Start server in thread
        def run_server():
            try:
                self.server.load_module()
                handler_class = self.server.create_handler()
                self.httpd = HTTPServer(("127.0.0.1", self.port), handler_class)
                self.httpd.serve_forever()
            except Exception:
                pass

        self.server_thread = threading.Thread(target=run_server, daemon=True)
        self.server_thread.start()

        # Wait for server to be ready
        max_attempts = 50
        for _ in range(max_attempts):
            try:
                self._request("GET", "/")
                break
            except Exception:
                time.sleep(0.1)

    def _request(
        self, method: str, path: str, data: dict = None, token: str = None
    ) -> dict:
        """Make HTTP request to server."""
        url = f"{self.base_url}{path}"
        headers = {"Content-Type": "application/json"}

        if token:
            headers["Authorization"] = f"Bearer {token}"

        body = json.dumps(data).encode() if data else None
        request = Request(url, data=body, headers=headers, method=method)

        try:
            with urlopen(request, timeout=5) as response:
                return json.loads(response.read().decode())
        except HTTPError as e:
            return json.loads(e.read().decode())

    def test_user_manager_creation(self) -> None:
        """Test UserManager creates users with unique roots."""
        user_mgr = UserManager(self.session_file)

        # Create first user
        result1 = user_mgr.create_user("user1", "pass1")
        self.assertIn("token", result1)
        self.assertIn("root_id", result1)
        self.assertEqual(result1["username"], "user1")

        # Create second user
        result2 = user_mgr.create_user("user2", "pass2")
        self.assertIn("token", result2)
        self.assertIn("root_id", result2)

        # Users should have different roots
        self.assertNotEqual(result1["root_id"], result2["root_id"])

        # Duplicate username should fail
        result3 = user_mgr.create_user("user1", "pass3")
        self.assertIn("error", result3)

    def test_user_manager_authentication(self) -> None:
        """Test UserManager authentication."""
        user_mgr = UserManager(self.session_file)

        # Create user
        create_result = user_mgr.create_user("testuser", "testpass")
        original_token = create_result["token"]

        # Authenticate with correct credentials
        auth_result = user_mgr.authenticate("testuser", "testpass")
        self.assertIsNotNone(auth_result)
        self.assertEqual(auth_result["username"], "testuser")
        self.assertEqual(auth_result["token"], original_token)

        # Wrong password
        auth_fail = user_mgr.authenticate("testuser", "wrongpass")
        self.assertIsNone(auth_fail)

        # Nonexistent user
        auth_fail2 = user_mgr.authenticate("nouser", "pass")
        self.assertIsNone(auth_fail2)

    def test_user_manager_token_validation(self) -> None:
        """Test UserManager token validation."""
        user_mgr = UserManager(self.session_file)

        # Create user
        result = user_mgr.create_user("validuser", "validpass")
        token = result["token"]

        # Valid token
        username = user_mgr.validate_token(token)
        self.assertEqual(username, "validuser")

        # Invalid token
        username = user_mgr.validate_token("invalid_token")
        self.assertIsNone(username)

    def test_server_user_creation(self) -> None:
        """Test user creation endpoint."""
        self._start_server()

        # Create user
        result = self._request(
            "POST",
            "/user/create",
            {"username": "alice", "password": "secret123"}
        )

        self.assertIn("username", result)
        self.assertIn("token", result)
        self.assertIn("root_id", result)
        self.assertEqual(result["username"], "alice")

    def test_server_user_login(self) -> None:
        """Test user login endpoint."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "bob", "password": "pass456"}
        )

        # Login with correct credentials
        login_result = self._request(
            "POST",
            "/user/login",
            {"username": "bob", "password": "pass456"}
        )

        self.assertIn("token", login_result)
        self.assertEqual(login_result["username"], "bob")
        self.assertEqual(login_result["root_id"], create_result["root_id"])

        # Login with wrong password
        login_fail = self._request(
            "POST",
            "/user/login",
            {"username": "bob", "password": "wrongpass"}
        )

        self.assertIn("error", login_fail)

    def test_server_authentication_required(self) -> None:
        """Test that protected endpoints require authentication."""
        self._start_server()

        # Try to access protected endpoint without token
        result = self._request("GET", "/functions")
        self.assertIn("error", result)
        self.assertIn("Unauthorized", result["error"])

    def test_server_list_functions(self) -> None:
        """Test listing functions endpoint."""
        self._start_server()

        # Create user and get token
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "funcuser", "password": "pass"}
        )
        token = create_result["token"]

        # List functions
        result = self._request("GET", "/functions", token=token)

        self.assertIn("functions", result)
        self.assertIn("add_numbers", result["functions"])
        self.assertIn("greet", result["functions"])

    def test_server_get_function_signature(self) -> None:
        """Test getting function signature."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "siguser", "password": "pass"}
        )
        token = create_result["token"]

        # Get signature
        result = self._request("GET", "/function/add_numbers", token=token)

        self.assertIn("signature", result)
        sig = result["signature"]
        self.assertIn("parameters", sig)
        self.assertIn("a", sig["parameters"])
        self.assertIn("b", sig["parameters"])
        self.assertTrue(sig["parameters"]["a"]["required"])
        self.assertTrue(sig["parameters"]["b"]["required"])

    def test_server_call_function(self) -> None:
        """Test calling a function endpoint."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "calluser", "password": "pass"}
        )
        token = create_result["token"]

        # Call add_numbers
        result = self._request(
            "POST",
            "/function/add_numbers",
            {"args": {"a": 10, "b": 25}},
            token=token
        )

        self.assertIn("result", result)
        self.assertEqual(result["result"], 35)

        # Call greet
        result2 = self._request(
            "POST",
            "/function/greet",
            {"args": {"name": "World"}},
            token=token
        )

        self.assertIn("result", result2)
        self.assertEqual(result2["result"], "Hello, World!")

    def test_server_call_function_with_defaults(self) -> None:
        """Test calling function with default parameters."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "defuser", "password": "pass"}
        )
        token = create_result["token"]

        # Call greet without name (should use default)
        result = self._request(
            "POST",
            "/function/greet",
            {"args": {}},
            token=token
        )

        self.assertIn("result", result)
        self.assertEqual(result["result"], "Hello, World!")

    def test_server_list_walkers(self) -> None:
        """Test listing walkers endpoint."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "walkuser", "password": "pass"}
        )
        token = create_result["token"]

        # List walkers
        result = self._request("GET", "/walkers", token=token)

        self.assertIn("walkers", result)
        self.assertIn("CreateTask", result["walkers"])
        self.assertIn("ListTasks", result["walkers"])
        self.assertIn("CompleteTask", result["walkers"])

    def test_server_get_walker_info(self) -> None:
        """Test getting walker information."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "infouser", "password": "pass"}
        )
        token = create_result["token"]

        # Get walker info
        result = self._request("GET", "/walker/CreateTask", token=token)

        self.assertIn("info", result)
        info = result["info"]
        self.assertIn("fields", info)
        self.assertIn("title", info["fields"])
        self.assertIn("priority", info["fields"])
        self.assertIn("_jac_spawn_node", info["fields"])

        # Check that priority has a default
        self.assertFalse(info["fields"]["priority"]["required"])
        self.assertIsNotNone(info["fields"]["priority"]["default"])

    def test_server_spawn_walker(self) -> None:
        """Test spawning a walker."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "spawnuser", "password": "pass"}
        )
        token = create_result["token"]

        # Spawn CreateTask walker
        result = self._request(
            "POST",
            "/walker/CreateTask",
            {"fields": {"title": "Test Task", "priority": 2}},
            token=token
        )

        # If error, print for debugging
        if "error" in result:
            print(f"\nWalker spawn error: {result['error']}")
            if "traceback" in result:
                print(f"Traceback:\n{result['traceback']}")

        self.assertIn("result", result)
        self.assertIn("reports", result)

        # Spawn ListTasks walker to verify task was created
        result2 = self._request(
            "POST",
            "/walker/ListTasks",
            {"fields": {}},
            token=token
        )

        self.assertIn("result", result2)

    def test_server_user_isolation(self) -> None:
        """Test that users have isolated graph spaces."""
        self._start_server()

        # Create two users
        user1 = self._request(
            "POST",
            "/user/create",
            {"username": "user1", "password": "pass1"}
        )
        user2 = self._request(
            "POST",
            "/user/create",
            {"username": "user2", "password": "pass2"}
        )

        token1 = user1["token"]
        token2 = user2["token"]

        # User1 creates a task
        self._request(
            "POST",
            "/walker/CreateTask",
            {"fields": {"title": "User1 Task", "priority": 1}},
            token=token1
        )

        # User2 creates a different task
        self._request(
            "POST",
            "/walker/CreateTask",
            {"fields": {"title": "User2 Task", "priority": 2}},
            token=token2
        )

        # Both users should have different root IDs
        self.assertNotEqual(user1["root_id"], user2["root_id"])

    def test_server_invalid_function(self) -> None:
        """Test calling nonexistent function."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "invaliduser", "password": "pass"}
        )
        token = create_result["token"]

        # Try to call nonexistent function
        result = self._request(
            "POST",
            "/function/nonexistent",
            {"args": {}},
            token=token
        )

        self.assertIn("error", result)

    def test_server_invalid_walker(self) -> None:
        """Test spawning nonexistent walker."""
        self._start_server()

        # Create user
        create_result = self._request(
            "POST",
            "/user/create",
            {"username": "invalidwalk", "password": "pass"}
        )
        token = create_result["token"]

        # Try to spawn nonexistent walker
        result = self._request(
            "POST",
            "/walker/NonExistentWalker",
            {"fields": {}},
            token=token
        )

        self.assertIn("error", result)

    def test_server_root_endpoint(self) -> None:
        """Test root endpoint returns API information."""
        self._start_server()

        result = self._request("GET", "/")

        self.assertIn("message", result)
        self.assertIn("endpoints", result)
        self.assertIn("POST /user/create", result["endpoints"])
        self.assertIn("GET /functions", result["endpoints"])
        self.assertIn("GET /walkers", result["endpoints"])

    def test_module_loading_and_introspection(self) -> None:
        """Test that module loads correctly and introspection works."""
        # Load module
        base, mod, mach = cli.proc_file_sess(
            self.fixture_abs_path("serve_api.jac"), ""
        )
        Jac.set_base_path(base)
        Jac.jac_import(
            target=mod,
            base_path=base,
            override_name="__main__",
            lng="jac",
        )

        # Create server
        server = JacAPIServer(
            module_name="__main__",
            session_path=self.session_file,
            port=9999,  # Different port, won't actually start
        )
        server.load_module()

        # Check module loaded
        self.assertIsNotNone(server.module)

        # Check functions discovered
        functions = server.get_functions()
        self.assertIn("add_numbers", functions)
        self.assertIn("greet", functions)

        # Check walkers discovered
        walkers = server.get_walkers()
        self.assertIn("CreateTask", walkers)
        self.assertIn("ListTasks", walkers)
        self.assertIn("CompleteTask", walkers)

        # Check introspection
        sig = server.introspect_callable(functions["add_numbers"])
        self.assertIn("parameters", sig)
        self.assertIn("a", sig["parameters"])
        self.assertIn("b", sig["parameters"])

        # Check walker introspection
        walker_info = server.introspect_walker(walkers["CreateTask"])
        self.assertIn("fields", walker_info)
        self.assertIn("title", walker_info["fields"])
        self.assertIn("priority", walker_info["fields"])

        mach.close()
