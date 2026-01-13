"""Jac TTG analysis pass.

This lightweight pass collects visit metadata for walker abilities so that
runtime structures can reference the information without re-parsing the
original Jac sources.
"""

from __future__ import annotations

from collections import defaultdict

import jaclang.pycore.unitree as uni
from jaclang.pycore.constant import TTG_VISIT_FIELD
from jaclang.pycore.constant import Tokens as Tok
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
        """Populate aggregate visit counts on each walker within a module."""
        walker_totals: dict[uni.Archetype, int] = defaultdict(int)
        for ability in module.get_all_sub_nodes(uni.Ability):
            self.cur_node = ability
            visit_count = len(ability.get_all_sub_nodes(uni.VisitStmt))
            walker = ability.find_parent_of_type(uni.Archetype)
            if not walker or walker.arch_type.name != Tok.KW_WALKER:
                continue
            walker_totals[walker] += visit_count

        for walker in module.get_all_sub_nodes(uni.Archetype):
            if walker.arch_type.name != Tok.KW_WALKER:
                continue
            total_visits = walker_totals.get(walker, 0)
            setattr(walker, TTG_VISIT_FIELD, total_visits)
            self.cur_node = walker
            self.log_info(
                f"Annotated walker {walker.name.sym_name} with {total_visits} visits"
            )
