"""Implementation of Jac Client configuration loader.

This delegates to the core JacConfig for all configuration operations,
reading from [plugins.client] for vite/ts config and [dependencies.npm]
for npm packages.
"""
import from jaclang.project.config { JacConfig }
import from pathlib { Path }
import from typing { Any }

"""Initialize config loader with project directory."""
impl JacClientConfig.init(self: JacClientConfig, project_dir: Path) {
    self.project_dir = project_dir;
    self.config_file = project_dir / 'jac.toml';
    self._config: (dict[(str, Any)] | None) = None;
    self._jac_config: (JacConfig | None) = None;
}

"""Get or load the core JacConfig."""
def _get_jac_config(self: JacClientConfig) -> JacConfig {
    if self._jac_config is None {
        if self.config_file.exists() {
            self._jac_config = JacConfig.load(self.config_file);
        } else {
            # Create a new config with project root
            self._jac_config = JacConfig();
            self._jac_config.toml_path = self.config_file;
            self._jac_config.project_root = self.project_dir;
        }
    }
    return self._jac_config;
}

"""Get package configuration (npm dependencies)."""
impl JacClientConfig.get_package_config(self: JacClientConfig) -> dict[str, Any] {
    config = self.load();
    return config.get('package', {});
}

"""Get Vite-specific configuration."""
impl JacClientConfig.get_vite_config(self: JacClientConfig) -> dict[str, Any] {
    config = self.load();
    return config.get('vite', {});
}

"""Get TypeScript-specific configuration for tsconfig.json customization."""
impl JacClientConfig.get_ts_config(self: JacClientConfig) -> dict[str, Any] {
    config = self.load();
    return config.get('ts', {});
}

"""Deep merge two dictionaries."""
impl JacClientConfig._deep_merge(
    self: JacClientConfig, base: dict[(str, Any)], override_dict: dict[(str, Any)]
) -> dict[str, Any] {
    result = base.copy();
    for (key, value) in override_dict.items() {
        if (
            (key in result)
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ) {
            result[key] = self._deep_merge(result[key], value);
        } else {
            result[key] = value;
        }
    }
    return result;
}

"""Load configuration from jac.toml, merging with defaults."""
impl JacClientConfig.load(self: JacClientConfig) -> dict[str, Any] {
    if (self._config is not None) {
        return self._config;
    }
    default_config = self._get_default_config();
    jac_config = _get_jac_config(self);
    # Get client plugin config from [plugins.client]
    client_config = jac_config.get_plugin_config('client');
    # Get npm dependencies from [dependencies.npm]
    npm_deps = jac_config.get_plugin_deps('npm');
    npm_dev_deps = npm_deps.get('dev', {})
    if isinstance(npm_deps.get('dev'), dict)
    else {};
    # Filter out 'dev' key from regular deps
    regular_deps = {
        k: v
        for (k, v) in npm_deps.items()
        if k != 'dev'
    };
    # Build user config in the expected internal format
    user_config: dict[str, Any] = {
        'vite': client_config.get('vite', {}),
        'ts': client_config.get('ts', {}),
        'package': {
            'name': jac_config.project.name,
            'version': jac_config.project.version,
            'description': jac_config.project.description,
            'dependencies': regular_deps,
            'devDependencies': npm_dev_deps
        }
    };
    self._config = self._deep_merge(default_config, user_config);
    return self._config;
}

"""Save configuration back to jac.toml using core JacConfig."""
impl JacClientConfig.save(self: JacClientConfig) -> None {
    jac_config = _get_jac_config(self);
    jac_config.save();
}

"""Add an npm dependency."""
impl JacClientConfig.add_dependency(
    self: JacClientConfig, name: str, version: str, is_dev: bool = False
) -> None {
    jac_config = _get_jac_config(self);
    jac_config.add_dependency(name, version, dev=is_dev, dep_type="npm");
    # Invalidate cache
    self._config = None;
}

"""Remove an npm dependency."""
impl JacClientConfig.remove_dependency(
    self: JacClientConfig, name: str, is_dev: bool = False
) -> bool {
    jac_config = _get_jac_config(self);
    result = jac_config.remove_dependency(name, dev=is_dev, dep_type="npm");
    # Invalidate cache
    self._config = None;
    return result;
}

"""Get default configuration structure."""
impl JacClientConfig._get_default_config(self: JacClientConfig) -> dict[str, Any] {
    return {
        'vite': {
            'plugins': [],
            'lib_imports': [],
            'build': {},
            'server': {},
            'resolve': {}
        },
        'ts': {'compilerOptions': {}, 'include': [], 'exclude': []},
        'package': {
            'name': '',
            'version': '1.0.0',
            'description': '',
            'dependencies': {},
            'devDependencies': {}
        }
    };
}
