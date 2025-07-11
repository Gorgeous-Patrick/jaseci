"""
Extract the possible visit statements.
"""

from typing import TypeAlias, Union
from dataclasses import dataclass
from jac.jaclang.compiler import unitree as uni

@dataclass
class VisitRestriction:
  to_node_type: str | None = None
  edge_type: str | None = None
  index: int = -1

Block: TypeAlias = list[Union[VisitRestriction, tuple["Block", "Block"]]]


def _get_visit_restriction_of_single_visit(visit_stmt: uni.VisitStmt) -> VisitRestriction:
      filters = visit_stmt.get_all_sub_nodes(uni.FilterCompr)
      edge_type = None if len(filters) else filters[0].get_all_sub_nodes(uni.Name)[0].value
      return VisitRestriction(edge_type=edge_type)

def get_visit_restrictions(ability: uni.Ability) -> Block: # This a very very rough method. 
  visit_stmts = ability.get_all_sub_nodes(uni.VisitStmt)
  return [_get_visit_restriction_of_single_visit(visit_stmt) for visit_stmt in visit_stmts]