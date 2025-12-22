"""Project configuration and management for Jac projects.

This module provides the jac.toml configuration system, including:
- JacConfig: Central configuration class for project settings
- Project discovery: Auto-detection of jac.toml in parent directories
- Dependency management: Install, add, remove dependencies
"""

# Note: We only import what's needed. The meta_importer handles Jac compilation.
# Import modules in dependency order to avoid circular imports
# Import dependencies module after config (it depends on config)
from jaclang.project import (
    config,  # type: ignore[attr-defined]  # noqa: F401
    dependencies,  # type: ignore[attr-defined]  # noqa: F401
)

# Re-export from config module
from jaclang.project.config import (
    BuildConfig,
    CacheConfig,
    CheckConfig,
    DotConfig,
    EnvironmentConfig,
    FormatConfig,
    JacConfig,
    PluginsConfig,
    ProjectConfig,
    RunConfig,
    ServeConfig,
    TestConfig,
    find_project_root,
    get_config,
    interpolate_env_vars,
    is_in_project,
    set_config,
)

# Re-export from dependencies module
from jaclang.project.dependencies import (
    DependencyInstaller,
    DependencyResolver,
    ResolvedDependency,
    add_packages_to_path,
    is_packages_in_path,
    remove_packages_from_path,
)

__all__ = [
    # Config
    "JacConfig",
    "ProjectConfig",
    "RunConfig",
    "BuildConfig",
    "TestConfig",
    "ServeConfig",
    "FormatConfig",
    "CheckConfig",
    "DotConfig",
    "CacheConfig",
    "PluginsConfig",
    "EnvironmentConfig",
    "get_config",
    "set_config",
    "find_project_root",
    "is_in_project",
    "interpolate_env_vars",
    # Dependencies
    "DependencyInstaller",
    "DependencyResolver",
    "ResolvedDependency",
    "add_packages_to_path",
    "remove_packages_from_path",
    "is_packages_in_path",
]
