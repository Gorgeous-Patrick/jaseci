"""Extract the possible visit statements."""

from dataclasses import dataclass

from jaclang.compiler import unitree as uni


@dataclass
class VisitRestriction:
    """Visit statement restrictions."""

    to_node_type: str | None = None
    edge_type: str | None = None
    index: int = -1


def get_visit_restriction_of_single_visit(
    visit_stmt: uni.VisitStmt,
) -> VisitRestriction:
    """Extract the visit statement restrictions."""
    filters = visit_stmt.get_all_sub_nodes(uni.FilterCompr)
    edge_type = (
        None if len(filters) else filters[0].get_all_sub_nodes(uni.Name)[0].value
    )
    return VisitRestriction(edge_type=edge_type)
