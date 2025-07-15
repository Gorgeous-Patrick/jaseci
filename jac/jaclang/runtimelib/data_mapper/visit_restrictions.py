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
        None if len(filters) == 0 else filters[0].get_all_sub_nodes(uni.Name)[0].value
    )
    return VisitRestriction(edge_type=edge_type)


def get_visit_restriction_of_walker(
    walker: uni.Archetype,
) -> dict[str, list[VisitRestriction]]:
    """Get all visit restrictions of a walker."""
    abilities = walker.get_all_sub_nodes(uni.Ability)
    return {
        ability.get_all_sub_nodes(uni.EventSignature)[0]
        .get_all_sub_nodes(uni.Name)[0]
        .value: [
            get_visit_restriction_of_single_visit(visit_stmt)
            for visit_stmt in ability.get_all_sub_nodes(uni.VisitStmt)
        ]
        for ability in abilities
    }
