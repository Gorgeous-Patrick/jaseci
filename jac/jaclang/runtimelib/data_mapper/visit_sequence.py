from dataclasses import dataclass
from typing import Generator, TypeAlias
import jaclang.compiler.unitree as uni

@dataclass
class VisitInfo:
    """A struct that stores the visit key information."""

    from_node_type: str
    walker_type: str
    edge_type: str
    async_edge: bool

VisitSequence: TypeAlias = list[VisitInfo]
_TracingInfo: TypeAlias = list[uni.UniCFGNode]

def get_visit_sequences(ability: uni.Ability) -> Generator[list[VisitInfo], None, None]:
    # print("=========")
    stack: list[_TracingInfo] = [[ability]]
    while (len(stack) > 0):
        path = stack.pop()
        node = path[-1]
        new_nodes = [new_node for new_node in node.bb_out if new_node not in path]
        new_paths = [path + [new_node] for new_node in new_nodes]
        for new_path in new_paths:
            new_node = new_path[-1]
            if len(new_node.bb_out) == 0:
                yield [_get_visit_info(new_node) for new_node in new_path if isinstance(new_node, uni.VisitStmt)]
            else:
                stack.append(new_path)
    

def _get_from_node_type_of_visit(visit_stmt: uni.VisitStmt) -> str:
    """Get the node type that the visit is from.

    For example, if a visit is in an ability:
        can xxx with XXX entry {...}, it will return XXX
    """
    ability = visit_stmt.parent_of_type(uni.Ability)
    return (
        ability.get_all_sub_nodes(uni.EventSignature)[0]
        .get_all_sub_nodes(uni.Name)[0]
        .value
    )

def _get_to_edge_type_of_visit(visit_stmt: uni.VisitStmt) -> str:
    filters = visit_stmt.get_all_sub_nodes(uni.FilterCompr)
    if len(filters) == 0:
        return "GenericEdge"
    return filters[0].get_all_sub_nodes(uni.Name)[0].value

def _get_walker_type_from_visit(visit_stmt: uni.VisitStmt) -> str:
    return (
        visit_stmt.find_parent_of_type(uni.Archetype)
        .get_all_sub_nodes(uni.Name)[0]
        .value
    )

def _get_visit_info(visit_stmt: uni.VisitStmt) -> VisitInfo:
    """Get the visit statement information."""
    from_node = _get_from_node_type_of_visit(visit_stmt)
    edge_type = _get_to_edge_type_of_visit(visit_stmt)
    walker_type = _get_walker_type_from_visit(visit_stmt)
    res = VisitInfo(
        from_node_type=from_node,
        walker_type=walker_type,
        edge_type=edge_type,
        async_edge=False,
    )
    return res

def get_walker_info(walker: uni.Archetype) -> dict[str, list[list[VisitInfo]]]:
    """Get the visit info of a walker."""
    visit_info: dict[str, list[list[VisitInfo]]] = {}
    abilities = walker.get_all_sub_nodes(uni.Ability)
    for ability in abilities:
        name = ability.get_all_sub_nodes(uni.EventSignature)[0].get_all_sub_nodes(uni.Name)[0].value
        visit_info[name] = list(get_visit_sequences(ability))
    # print(visit_info)
        
    return visit_info
