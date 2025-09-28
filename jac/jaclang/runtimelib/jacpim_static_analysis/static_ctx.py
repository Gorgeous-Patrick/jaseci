"""JacPIM Static CTX is a global context for the JacPIM system in the static analysis phase."""

from typing import Any

from jaclang.runtimelib.archetype import (
    EdgeAnchor,
    EdgeArchetype,
    NodeAnchor,
    NodeArchetype,
)

from .info_extract import _extract_name


class JacPIMStaticCtx:
    """Global static context for JacPIM."""

    all_nodes: list[NodeArchetype] | None = None
    all_edges: list[EdgeArchetype] | None = None

    @classmethod
    def _get_graph_nodes_and_edges(
        cls,
        jctx: Any,  # noqa: ANN401, to avoid circular dependency
    ) -> None:
        all_nodes = [
            node.archetype
            for node in jctx.mem.__mem__.values()
            if isinstance(node, NodeAnchor) and _extract_name(node.archetype) != "Root"
        ]
        all_edges = [
            edge.archetype
            for edge in jctx.mem.__mem__.values()
            if isinstance(edge, EdgeAnchor)
            and _extract_name(edge.target.archetype) != "Root"
            and _extract_name(edge.source.archetype) != "Root"
        ]
        cls.all_nodes, cls.all_edges = all_nodes, all_edges

    @classmethod
    def get_all_nodes(cls) -> list[NodeArchetype]:
        """Get a list of all nodes in the context."""
        if cls.all_nodes is None:
            raise RuntimeError("all_nodes is None")
        return cls.all_nodes

    @classmethod
    def get_all_edges(cls) -> list[EdgeArchetype]:
        """Get a list of all edges in the context."""
        if cls.all_edges is None:
            raise RuntimeError("all_edges is None")
        return cls.all_edges
