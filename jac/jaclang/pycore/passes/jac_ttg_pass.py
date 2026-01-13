"""Jac TTG analysis pass.

This lightweight pass collects visit metadata for walker abilities so that
runtime structures can reference the information without re-parsing the
original Jac sources.
"""

from __future__ import annotations

import jaclang.pycore.unitree as uni
from jaclang.pycore.passes.transform import Transform


class JacTTGPass(Transform[uni.Module, uni.Module]):
    """Annotate abilities with visit counts for TTG generation."""

    def transform(self, ir_in: uni.Module) -> uni.Module:
        """Process every module reachable from ir_in."""
        modules = [ir_in, *ir_in.get_all_sub_nodes(uni.Module)]
        for module in modules:
            self.cur_node = module
            self.log_info(f"JacTTGPass processing module {module.loc.mod_path}")
            self._annotate_module(module)
        return ir_in

    def _annotate_module(self, module: uni.Module) -> None:
        """Populate visit counts on each ability within a module."""
        for ability in module.get_all_sub_nodes(uni.Ability):
            self.cur_node = ability
            visit_count = len(ability.get_all_sub_nodes(uni.VisitStmt))
            ability.gen.visits = visit_count
            self.log_info(
                f"Annotated ability {ability.sym_name} with {visit_count} visits"
            )
