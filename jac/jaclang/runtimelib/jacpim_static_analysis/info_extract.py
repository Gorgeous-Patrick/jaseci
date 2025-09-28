"""Extract static information from node, edges and walkers."""

from dataclasses import dataclass

from jaclang.runtimelib.archetype import Archetype, EdgeArchetype, NodeArchetype

from .size_calc import calculate_size


@dataclass
class JacPIMNodeInfo:
    """All information JacPIM system needs from a node instance."""

    type_name: str
    display_name: str | None
    node_size_bytes: int


@dataclass
class JacPIMEdgeInfo:
    """All information JacPIM system needs from a node instance."""

    type_name: str


def _extract_name(input: Archetype) -> str:
    """Split the name by left bracket."""
    return str(input).split(chr(40))[0]


def get_node_info_from_node_arch(node: NodeArchetype) -> JacPIMNodeInfo:
    """Extract node information."""
    return JacPIMNodeInfo(
        type_name=_extract_name(node),
        display_name=getattr(node, "id", None),
        node_size_bytes=calculate_size(node),
    )


def get_edge_info_from_edge_arch(edge: EdgeArchetype) -> JacPIMEdgeInfo:
    """Extract edge information."""
    return JacPIMEdgeInfo(type_name=_extract_name(edge))
