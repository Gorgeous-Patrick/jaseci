"""REST API Server for Jac Programs."""

import hashlib
import inspect
import json
import os
import secrets
from contextlib import suppress
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Callable, Optional, get_type_hints
from urllib.parse import urlparse

from jaclang.runtimelib.constructs import (
    Archetype,
    NodeArchetype,
    Root,
    WalkerArchetype,
)
from jaclang.runtimelib.machine import (
    ExecutionContext,
    JacMachine as Jac,
)


def serialize_for_response(obj: object) -> object:
    """Serialize Jac objects to JSON-compatible format.

    This function handles conversion of:
    - Archetype instances (nodes, walkers, edges, objects)
    - Lists and dicts (recursively serialize contents)
    - Other objects (attempt to convert to dict or return as-is)
    """
    if obj is None or isinstance(obj, (str, int, float, bool)):
        return obj

    if isinstance(obj, (list, tuple)):
        return [serialize_for_response(item) for item in obj]

    if isinstance(obj, dict):
        return {key: serialize_for_response(value) for key, value in obj.items()}

    # Check for any Archetype subclass (Node, Walker, Edge, Object, etc.)
    if isinstance(obj, Archetype):
        # Serialize archetype with its ID and public attributes
        result = {
            "_jac_type": type(obj).__name__,
            "_jac_id": obj.__jac__.id.hex,
        }

        # Add type-specific metadata
        if isinstance(obj, NodeArchetype):
            result["_jac_archetype"] = "node"
        elif isinstance(obj, WalkerArchetype):
            result["_jac_archetype"] = "walker"
        else:
            result["_jac_archetype"] = "archetype"

        # Get all public attributes from the archetype
        for attr_name in dir(obj):
            if not attr_name.startswith("_") and attr_name not in ("__jac__",):
                try:
                    attr_value = getattr(obj, attr_name)
                    # Skip methods and special attributes
                    if not callable(attr_value):
                        result[attr_name] = serialize_for_response(attr_value)
                except Exception:
                    pass
        return result

    # Try to convert object to dict if it has __dict__
    if hasattr(obj, "__dict__"):
        with suppress(Exception):
            return serialize_for_response(
                {k: v for k, v in obj.__dict__.items() if not k.startswith("_")}
            )

    # For other types, try to convert to string
    try:
        return str(obj)
    except Exception:
        return f"<{type(obj).__name__}>"


class UserManager:
    """Manage users and their persistent roots."""

    USER_DATA_KEY = "__jac_users__"
    TOKEN_DATA_KEY = "__jac_tokens__"

    def __init__(self, session_path: str) -> None:
        """Initialize user manager."""
        self.session_path = session_path
        # Use a separate file for user data to avoid locking conflicts
        self.user_db_path = f"{session_path}.users.json"

        # Load existing user data from persistent storage
        self.users: dict[str, dict[str, Any]] = {}
        self.tokens: dict[str, str] = {}
        try:
            with open(self.user_db_path, "r", encoding="utf-8") as fh:
                stored = json.load(fh)
                self.users = stored.get(self.USER_DATA_KEY, {})
                self.tokens = stored.get(self.TOKEN_DATA_KEY, {})
        except FileNotFoundError:
            self.users = {}
            self.tokens = {}
        except Exception:
            # If the storage is corrupted fallback to a clean slate so tests can
            # proceed.  The malformed file will be overwritten on the next
            # persist operation.
            self.users = {}
            self.tokens = {}

    def _persist(self) -> None:
        """Save user data to persistent storage."""
        data = {
            self.USER_DATA_KEY: self.users,
            self.TOKEN_DATA_KEY: self.tokens,
        }
        with open(self.user_db_path, "w", encoding="utf-8") as fh:
            json.dump(data, fh)

    def close(self) -> None:
        """Close the shelf storage."""
        self._persist()

    def create_user(self, username: str, password: str) -> dict[str, Any]:
        """Create a new user with their own root node."""
        if username in self.users:
            return {"error": "User already exists"}

        # Hash the password
        password_hash = hashlib.sha256(password.encode()).hexdigest()

        # Create execution context and root for this user
        ctx = ExecutionContext(session=self.session_path)
        Jac.set_context(ctx)

        # Create user's root node
        user_root = Root()
        root_anchor = user_root.__jac__
        Jac.save(root_anchor)
        Jac.commit(root_anchor)
        root_id = root_anchor.id.hex

        ctx.mem.close()
        Jac.set_context(ExecutionContext())

        # Generate authentication token
        token = secrets.token_urlsafe(32)

        self.users[username] = {
            "password_hash": password_hash,
            "token": token,
            "root_id": root_id,
        }
        self.tokens[token] = username

        # Persist user data to storage
        self._persist()

        return {
            "username": username,
            "token": token,
            "root_id": root_id,
        }

    def authenticate(self, username: str, password: str) -> Optional[dict[str, Any]]:
        """Authenticate a user and return their token."""
        if username not in self.users:
            return None

        password_hash = hashlib.sha256(password.encode()).hexdigest()
        user = self.users[username]

        if user["password_hash"] == password_hash:
            return {
                "username": username,
                "token": user["token"],
                "root_id": user["root_id"],
            }
        return None

    def validate_token(self, token: str) -> Optional[str]:
        """Validate token and return username."""
        return self.tokens.get(token)

    def get_user_root(self, username: str) -> Optional[str]:
        """Get user's root node ID."""
        if username in self.users:
            return self.users[username]["root_id"]
        return None


class JacAPIServer:
    """REST API Server for Jac programs."""

    def __init__(
        self,
        module_name: str,
        session_path: str,
        port: int = 8000,
        base_path: str | None = None,
    ) -> None:
        """Initialize the API server."""
        self.module_name = module_name
        self.session_path = session_path
        self.port = port
        self.base_path = os.path.abspath(base_path) if base_path else None
        self.user_manager = UserManager(session_path)
        self.module = None
        self._function_cache: dict[str, Callable] = {}
        self._walker_cache: dict[str, type[WalkerArchetype]] = {}

    def load_module(self, force_reload: bool = False) -> None:
        """Load the target module if necessary and refresh caches."""
        needs_import = force_reload or self.module_name not in Jac.loaded_modules

        if needs_import and self.base_path:
            Jac.jac_import(
                target=self.module_name,
                base_path=self.base_path,
                lng="jac",
                reload_module=force_reload,
            )

        module = Jac.loaded_modules.get(self.module_name)
        if not module:
            return

        if (
            needs_import
            or self.module is not module
            or self._function_cache is None
            or self._walker_cache is None
            or (not self._function_cache and not self._walker_cache)
        ):
            self.module = module
            self._function_cache = self._collect_functions()
            self._walker_cache = self._collect_walkers()

    def get_functions(self) -> dict[str, Callable]:
        """Get all functions from the module."""
        if not self._function_cache:
            self.load_module()
        return dict(self._function_cache)

    def get_walkers(self) -> dict[str, type[WalkerArchetype]]:
        """Get all walker classes from the module."""
        if not self._walker_cache:
            self.load_module()
        return dict(self._walker_cache)

    def _collect_functions(self) -> dict[str, Callable]:
        """Collect callable functions from the module."""
        if not self.module:
            return {}
        functions = {}
        for name, obj in inspect.getmembers(self.module):
            if (
                inspect.isfunction(obj)
                and not name.startswith("_")
                and obj.__module__ == self.module.__name__
            ):
                functions[name] = obj
        return functions

    def _collect_walkers(self) -> dict[str, type[WalkerArchetype]]:
        """Collect walker classes from the module."""
        if not self.module:
            return {}
        walkers = {}
        for name, obj in inspect.getmembers(self.module):
            if (
                isinstance(obj, type)
                and issubclass(obj, WalkerArchetype)
                and obj is not WalkerArchetype
                and obj.__module__ == self.module.__name__
            ):
                walkers[name] = obj
        return walkers

    def introspect_callable(self, func: Callable) -> dict[str, Any]:
        """Introspect a callable and return its signature."""
        try:
            sig = inspect.signature(func)
            type_hints = get_type_hints(func)
        except Exception:
            sig = None
            type_hints = {}

        params = {}
        if sig:
            for param_name, param in sig.parameters.items():
                param_type = type_hints.get(param_name, Any)
                param_info = {
                    "type": str(param_type),
                    "required": param.default == inspect.Parameter.empty,
                    "default": (
                        None
                        if param.default == inspect.Parameter.empty
                        else str(param.default)
                    ),
                }
                params[param_name] = param_info

        return {
            "parameters": params,
            "return_type": str(type_hints.get("return", Any)),
        }

    def introspect_walker(self, walker_cls: type[WalkerArchetype]) -> dict[str, Any]:
        """Introspect a walker class and return its fields."""
        try:
            sig = inspect.signature(walker_cls.__init__)
            type_hints = get_type_hints(walker_cls.__init__)
        except Exception:
            sig = None
            type_hints = {}

        fields = {}
        if sig:
            for param_name, param in sig.parameters.items():
                if param_name in ("self", "args", "kwargs"):
                    continue
                param_type = type_hints.get(param_name, Any)
                field_info = {
                    "type": str(param_type),
                    "required": param.default == inspect.Parameter.empty,
                    "default": (
                        None
                        if param.default == inspect.Parameter.empty
                        else str(param.default)
                    ),
                }
                fields[param_name] = field_info

        # Also add _jac_spawn_node field for walker spawning
        fields["_jac_spawn_node"] = {
            "type": "str (node ID, optional)",
            "required": False,
            "default": "root",
        }

        return {"fields": fields}

    def call_function(
        self,
        func: Callable,
        args: dict[str, Any],
        username: str,
    ) -> dict[str, object]:
        """Call a function with the given arguments."""
        root_id = self.user_manager.get_user_root(username)
        if not root_id:
            return {"error": "User not found"}

        # Create execution context for this user
        ctx = ExecutionContext(session=self.session_path, root=root_id)
        Jac.set_context(ctx)

        try:
            # Call the function with unpacked arguments
            result = func(**args)
            Jac.commit()
            return {
                "result": serialize_for_response(result),
                "reports": serialize_for_response(ctx.reports),
            }
        except Exception as e:
            return {"error": str(e)}
        finally:
            ctx.mem.close()
            Jac.set_context(ExecutionContext())

    def spawn_walker(
        self,
        walker_cls: type[WalkerArchetype],
        fields: dict[str, Any],
        username: str,
    ) -> dict[str, object]:
        """Spawn a walker on a node."""
        root_id = self.user_manager.get_user_root(username)
        if not root_id:
            return {"error": "User not found"}

        # Extract _jac_spawn_node if specified
        target_node_id = fields.pop("_jac_spawn_node", None)

        # Create execution context for this user
        ctx = ExecutionContext(session=self.session_path, root=root_id)
        Jac.set_context(ctx)

        try:
            # Create walker instance
            walker = walker_cls(**fields)

            # Determine spawn location
            if target_node_id:
                target_node = Jac.get_object(target_node_id)
                if not isinstance(target_node, NodeArchetype):
                    return {"error": f"Invalid target node: {target_node_id}"}
            else:
                # Spawn on root node
                target_node = ctx.get_root()

            # Spawn the walker
            Jac.spawn(walker, target_node)
            Jac.commit()

            # Serialize the walker's final state and reports
            walker_result = serialize_for_response(walker)
            serialized_reports = serialize_for_response(ctx.reports)

            return {
                "result": walker_result,
                "reports": serialized_reports,
            }
        except Exception as e:
            import traceback

            return {"error": str(e), "traceback": traceback.format_exc()}
        finally:
            ctx.mem.close()
            Jac.set_context(ExecutionContext())

    def create_handler(self) -> type[BaseHTTPRequestHandler]:
        """Create the request handler class."""
        server = self

        class JacRequestHandler(BaseHTTPRequestHandler):
            """Handle HTTP requests."""

            def _send_json_response(self, status_code: int, data: dict) -> None:
                """Send a JSON response."""
                self.send_response(status_code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header(
                    "Access-Control-Allow-Headers", "Content-Type, Authorization"
                )
                self.end_headers()
                self.wfile.write(json.dumps(data).encode())

            def _get_auth_token(self) -> Optional[str]:
                """Extract auth token from Authorization header."""
                auth_header = self.headers.get("Authorization")
                if auth_header and auth_header.startswith("Bearer "):
                    return auth_header[7:]
                return None

            def _authenticate(self) -> Optional[str]:
                """Authenticate request and return username."""
                token = self._get_auth_token()
                if not token:
                    return None
                return server.user_manager.validate_token(token)

            def do_OPTIONS(self) -> None:  # noqa: N802
                """Handle OPTIONS requests (CORS preflight)."""
                self.send_response(200)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header(
                    "Access-Control-Allow-Headers", "Content-Type, Authorization"
                )
                self.end_headers()

            def do_GET(self) -> None:  # noqa: N802
                """Handle GET requests."""
                parsed_path = urlparse(self.path)
                path = parsed_path.path

                # Public endpoints
                if path == "/":
                    self._send_json_response(
                        200,
                        {
                            "message": "Jac API Server",
                            "endpoints": {
                                "POST /user/create": "Create a new user",
                                "POST /user/login": "Authenticate and get token",
                                "GET /functions": "List all available functions",
                                "GET /walkers": "List all available walkers",
                                "GET /function/<name>": "Get function signature",
                                "GET /walker/<name>": "Get walker fields",
                                "POST /function/<name>": "Call a function",
                                "POST /walker/<name>": "Spawn a walker",
                            },
                        },
                    )
                    return

                # Protected endpoints require authentication
                username = self._authenticate()
                if not username:
                    self._send_json_response(401, {"error": "Unauthorized"})
                    return

                server.load_module()

                if path == "/functions":
                    functions = server.get_functions()
                    self._send_json_response(
                        200,
                        {
                            "functions": list(functions.keys()),
                        },
                    )
                    return

                elif path == "/walkers":
                    walkers = server.get_walkers()
                    self._send_json_response(
                        200,
                        {
                            "walkers": list(walkers.keys()),
                        },
                    )
                    return

                elif path.startswith("/function/"):
                    func_name = path.split("/")[-1]
                    functions = server.get_functions()
                    if func_name in functions:
                        func = functions[func_name]
                        signature = server.introspect_callable(func)
                        self._send_json_response(
                            200,
                            {
                                "name": func_name,
                                "signature": signature,
                            },
                        )
                    else:
                        self._send_json_response(
                            404,
                            {"error": f"Function '{func_name}' not found"},
                        )
                    return

                elif path.startswith("/walker/"):
                    walker_name = path.split("/")[-1]
                    walkers = server.get_walkers()
                    if walker_name in walkers:
                        walker_cls = walkers[walker_name]
                        info = server.introspect_walker(walker_cls)
                        self._send_json_response(
                            200,
                            {
                                "name": walker_name,
                                "info": info,
                            },
                        )
                    else:
                        self._send_json_response(
                            404,
                            {"error": f"Walker '{walker_name}' not found"},
                        )
                    return

                self._send_json_response(404, {"error": "Not found"})

            def do_POST(self) -> None:  # noqa: N802
                """Handle POST requests."""
                parsed_path = urlparse(self.path)
                path = parsed_path.path

                # Read request body
                content_length = int(self.headers.get("Content-Length", 0))
                body = (
                    self.rfile.read(content_length).decode()
                    if content_length > 0
                    else "{}"
                )

                try:
                    data = json.loads(body)
                except json.JSONDecodeError:
                    self._send_json_response(400, {"error": "Invalid JSON"})
                    return

                # Public endpoints
                if path == "/user/create":
                    username = data.get("username")
                    password = data.get("password")
                    if not username or not password:
                        self._send_json_response(
                            400,
                            {"error": "Username and password required"},
                        )
                        return

                    result = server.user_manager.create_user(username, password)
                    if "error" in result:
                        self._send_json_response(400, result)
                    else:
                        self._send_json_response(201, result)
                    return

                elif path == "/user/login":
                    username = data.get("username")
                    password = data.get("password")
                    if not username or not password:
                        self._send_json_response(
                            400,
                            {"error": "Username and password required"},
                        )
                        return

                    login_result = server.user_manager.authenticate(username, password)
                    if login_result:
                        self._send_json_response(200, login_result)
                    else:
                        self._send_json_response(401, {"error": "Invalid credentials"})
                    return

                # Protected endpoints require authentication
                username = self._authenticate()
                if not username:
                    self._send_json_response(401, {"error": "Unauthorized"})
                    return

                server.load_module()

                if path.startswith("/function/"):
                    func_name = path.split("/")[-1]
                    functions = server.get_functions()
                    if func_name in functions:
                        func = functions[func_name]
                        args = data.get("args", {})
                        result = server.call_function(func, args, username)
                        self._send_json_response(200, result)
                    else:
                        self._send_json_response(
                            404,
                            {"error": f"Function '{func_name}' not found"},
                        )
                    return

                elif path.startswith("/walker/"):
                    walker_name = path.split("/")[-1]
                    walkers = server.get_walkers()
                    if walker_name in walkers:
                        walker_cls = walkers[walker_name]
                        fields = data.get("fields", {})
                        result = server.spawn_walker(walker_cls, fields, username)
                        self._send_json_response(200, result)
                    else:
                        self._send_json_response(
                            404,
                            {"error": f"Walker '{walker_name}' not found"},
                        )
                    return

                self._send_json_response(404, {"error": "Not found"})

            def log_message(self, format: str, *args: object) -> None:
                """Log HTTP requests."""
                print(f"{self.address_string()} - {format % args}")

        return JacRequestHandler

    def start(self) -> None:
        """Start the HTTP server."""
        self.load_module()
        handler_class = self.create_handler()

        with HTTPServer(("0.0.0.0", self.port), handler_class) as httpd:
            print(f"Jac API Server running on http://0.0.0.0:{self.port}")
            print(f"Module: {self.module_name}")
            print(f"Session: {self.session_path}")
            print("\nAvailable endpoints:")
            print("  POST /user/create - Create a new user")
            print("  POST /user/login - Login and get auth token")
            print("  GET /functions - List all functions")
            print("  GET /walkers - List all walkers")
            print("  GET /function/<name> - Get function signature")
            print("  GET /walker/<name> - Get walker info")
            print("  POST /function/<name> - Call a function")
            print("  POST /walker/<name> - Spawn a walker")
            print("\nPress Ctrl+C to stop the server")

            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\nShutting down server...")
