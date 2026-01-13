"""Jac TTG analysis pass.

This lightweight pass collects visit metadata for walker abilities so that
runtime structures can reference the information without re-parsing the
original Jac sources.
"""

from __future__ import annotations

from dataclasses import dataclass

from jaclang.pycore import unitree as uni
from jaclang.pycore.constant import TTG_VISIT_FIELD
from jaclang.pycore.constant import Tokens as Tok
from jaclang.pycore.passes.transform import Transform


class JacTTGPass(Transform[uni.Module, uni.Module]):
    """Annotate abilities with visit counts for TTG generation."""

    @dataclass(frozen=True)
    class VisitTypeAST:
        from_node_type: uni.Archetype
        edge_type: uni.Archetype | None

        def __str__(self) -> str:
            if self.edge_type is None:
                edge_name = "GenericEdge"
            else:
                edge_name = self.edge_type.name.value
            return f"Visit(from={self.from_node_type.name.value}, edge={edge_name})"

    def resolve_to_archetype(self, scope_src: uni.UniNode, name: str) -> uni.Archetype:
        scope = scope_src.find_parent_of_type(uni.UniScopeNode)
        if scope is None:
            raise RuntimeError(f"Lookup failed. Name: {name}")
        result = scope.lookup(name)
        if result is None:
            raise RuntimeError(f"Lookup failed. Name: {name}")
        archetype = result.decl.find_parent_of_type(uni.Archetype)
        if archetype is None:
            raise RuntimeError(f"Archetype lookup failed. Name: {name}")
        return archetype

    def _get_to_edge_type_of_visit(
        self, from_node_type: uni.Archetype, visit_stmt: uni.VisitStmt
    ) -> VisitTypeAST:
        filters = visit_stmt.get_all_sub_nodes(uni.FilterCompr)
        if len(filters) == 0:
            return self.VisitTypeAST(from_node_type=from_node_type, edge_type=None)
        # return
        edge_type_name = filters[0].get_all_sub_nodes(uni.Name)[0].value
        edge_type = self.resolve_to_archetype(visit_stmt, edge_type_name)
        return self.VisitTypeAST(from_node_type=from_node_type, edge_type=edge_type)

    def _get_all_visits_for_a_walker(self, walker: uni.Archetype) -> list[VisitTypeAST]:
        res = []
        abilities = walker.get_all_sub_nodes(uni.Ability)
        for ability in abilities:
            event_sigs = ability.get_all_sub_nodes(uni.EventSignature)
            if len(event_sigs) == 0:
                continue
            # Get the name of the node type
            node_type_names = event_sigs[0].get_all_sub_nodes(uni.Name)
            # TODO: SUPPORT SPECIFIC NODE EVENT SIGNATURES.
            if len(node_type_names) == 0:
                raise RuntimeError("Visit event missing node type name.")
            node_type_name = node_type_names[0]

            node_type = self.resolve_to_archetype(node_type_name, node_type_name.value)
            res += [
                self._get_to_edge_type_of_visit(node_type, visit_stmt)
                for visit_stmt in ability.get_all_sub_nodes(uni.VisitStmt)
            ]
        return res

    def transform(self, ir_in: uni.Module) -> uni.Module:
        """Process every module reachable from ir_in."""
        modules = [ir_in, *ir_in.get_all_sub_nodes(uni.Module)]
        for module in modules:
            self.cur_node = module
            self.log_info(f"JacTTGPass processing module {module.loc.mod_path}")
            self._annotate_module(module)
        return ir_in

    def _annotate_module(self, module: uni.Module) -> None:
        """Populate visit metadata on each walker within a module."""
        for walker in module.get_all_sub_nodes(uni.Archetype):
            if walker.arch_type.name != Tok.KW_WALKER:
                continue
            visit_types = self._get_all_visits_for_a_walker(walker)
            setattr(walker, TTG_VISIT_FIELD, visit_types)
            self.cur_node = walker
            self.log_info(
                f"Annotated walker {walker.name.sym_name} with {len(visit_types)} visits"
            )
