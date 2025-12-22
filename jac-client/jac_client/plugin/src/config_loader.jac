"""Configuration loader for Jac Client build system.

This module provides a thin wrapper around the core JacConfig,
providing client-specific configuration access.
"""
import from pathlib { Path }
import from typing { Any }
import from jaclang.project.config { JacConfig }

"""Wrapper around core JacConfig for client-specific configuration."""
class JacClientConfig {
    def init(self: JacClientConfig, project_dir: Path);
    def _get_default_config(self: JacClientConfig) -> dict[str, Any];
    def load(self: JacClientConfig) -> dict[str, Any];
    def _deep_merge(
        self: JacClientConfig, base: dict[(str, Any)], override_dict: dict[(str, Any)]
    ) -> dict[str, Any];

    def save(self: JacClientConfig) -> None;
    def get_vite_config(self: JacClientConfig) -> dict[str, Any];
    def get_ts_config(self: JacClientConfig) -> dict[str, Any];
    def get_package_config(self: JacClientConfig) -> dict[str, Any];
    def add_dependency(
        self: JacClientConfig, name: str, version: str, is_dev: bool = False
    ) -> None;

    def remove_dependency(
        self: JacClientConfig, name: str, is_dev: bool = False
    ) -> bool;
}
