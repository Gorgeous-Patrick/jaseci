"""File covering plugin implementation."""
import os;
import pathlib;
import from dotenv { load_dotenv }
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.command { Arg, ArgKind, CommandPriority }
import from jaclang.pycore.runtime { hookimpl, plugin_manager }
import from jaclang.runtimelib.context { ExecutionContext }
import from .context { JScaleExecutionContext }
import from .kubernetes.docker_impl { build_and_push_docker }
import from .kubernetes.K8s { deploy_K8s }
import from .kubernetes.utils { cleanup_K8s_resources }
import from .serve { JacAPIServer }

"""Jac CLI."""
class JacCmd {
    """Create Jac CLI cmds."""
    @hookimpl
    static def create_cmd -> None {
        """Jac Scale functionality.""";
        registry = get_registry();

        @registry.command(
            name="scale",
            help="Deploy Jac application to Kubernetes",
            args=[
                Arg.create(
                    "file_path", kind=ArgKind.POSITIONAL, help="Path to .jac file"
                ),
                Arg.create(
                    "build",
                    typ=bool,
                    default=False,
                    help="Build and push Docker image",
                    short="b"
                ),

            ],
            examples=[
                ("jac scale app.jac", "Deploy without rebuilding"),
                ("jac scale app.jac --build", "Build and deploy"),

            ],
            group="deployment",
            priority=CommandPriority.PLUGIN,
            source="jac-scale"
        )
        def scale(file_path: str, build: bool = False) -> int {
            if not os.path.exists(file_path) {
                raise FileNotFoundError(f"File not found: '{file_path}'") ;
            }
            code_folder = os.path.dirname(file_path) or '.';
            dotenv_path = os.path.join(code_folder, '.env');
            load_dotenv(dotenv_path);
            code_folder = os.path.relpath(code_folder);
            code_folder = pathlib.Path(code_folder).as_posix();
            base_file_path = os.path.basename(file_path);
            if build {
                build_and_push_docker(code_folder);
            }
            deploy_K8s(code_folder, base_file_path, build);
            return 0;
        }

        @registry.command(
            name="destroy",
            help="Remove Kubernetes deployment",
            args=[
                Arg.create(
                    "file_path", kind=ArgKind.POSITIONAL, help="Path to .jac file"
                ),

            ],
            examples=[("jac destroy app.jac", "Remove deployment for app"), ],
            group="deployment",
            priority=CommandPriority.PLUGIN,
            source="jac-scale"
        )
        def destroy(file_path: str) -> int {
            if not os.path.exists(file_path) {
                raise FileNotFoundError(f"File not found: '{file_path}'") ;
            }
            code_folder = os.path.dirname(file_path) or '.';
            dotenv_path = os.path.join(code_folder, '.env');
            load_dotenv(dotenv_path);
            cleanup_K8s_resources();
            return 0;
        }
    }
}

"""Jac Scale Plugin Implementation."""
class JacScalePlugin {
    @hookimpl
    static def create_j_context(
        session: (str | None) = None, <>root: (str | None) = None
    ) -> ExecutionContext {
        return JScaleExecutionContext(session=session, <>root=<>root);
    }

    """Provide jac-scale's enhanced JacAPIServer class."""
    @hookimpl
    static def get_api_server_class -> type {
        return JacAPIServer;
    }
}

# Pluggy's varnames() puts parameters with defaults into kwargnames, not argnames.
# But _multicall only passes argnames to hook implementations.
# JacRuntimeInterfaceImpl strips defaults via generate_plugin_helpers, so we must too.
import inspect;
glob func = JacScalePlugin.create_j_context,
     sig = inspect.signature(func),
     sig_nodef = sig.replace(
         parameters=[
             p.replace(default=inspect.Parameter.empty)
             for p in sig.parameters.values()
         ]
     );

with entry {
    func.__signature__ = sig_nodef;
    plugin_manager.register(JacScalePlugin());
}
