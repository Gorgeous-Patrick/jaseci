"""JacPIM Static CTX is a global context for the JacPIM system in the static analysis phase."""

from typing import Any

from jaclang.runtimelib.archetype import (
    EdgeAnchor,
    EdgeArchetype,
    NodeAnchor,
    NodeArchetype,
)

import networkx as nx

from .info_extract import _extract_name


class JacPIMStaticCtx:
    """Global static context for JacPIM."""

    all_nodes: list[NodeArchetype] | None = None
    all_edges: list[EdgeArchetype] | None = None
    network: nx.DiGraph | None = None

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

    @classmethod
    def get_networkx(cls) -> nx.DiGraph:
        """Get the networkx construction for JacPIM."""
        if cls.network is not None:
            return cls.network

        graph = nx.DiGraph()

        for idx, node_arch in enumerate(cls.get_all_nodes()):
            # Add node with detailed annotations
            graph.add_node(idx, archetype=node_arch)

        # Assign colors by node_type
        # node_types = nx.get_node_attributes(graph, "node_type")
        # unique_types = sorted(set(node_types.values()))
        # cmap = plt.get_cmap("tab10")
        # color_map = {t: cmap(i) for i, t in enumerate(unique_types)}

        # Store color in node attribute
        # for idx, node in enumerate(graph.nodes()):
        #     graph.nodes[node]["color"] = color_map[graph.nodes[node]["node_type"]]
        #     graph.nodes[node]["is_starting_node"] = (
        #         len(cls.get_all_nodes()[idx].spawned_walker_archetypes)
        #     ) > 0

        for _idx, edge_arch in enumerate(cls.get_all_edges()):
            graph.add_edge(
                cls.get_all_nodes().index(edge_arch.__jac__.source.archetype),
                cls.get_all_nodes().index(edge_arch.__jac__.target.archetype),
                archetype=edge_arch,
            )

        return graph
