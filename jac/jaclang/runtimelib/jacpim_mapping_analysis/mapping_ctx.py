"""JacPIM Mapping Phase global context."""

import jaclang.compiler.unitree as uni
from jaclang.runtimelib.archetype import NodeArchetype, WalkerArchetype
from jaclang.runtimelib.jacpim_mapping_analysis.temporal_trace_graph import (
    get_access_pattern_single_walker,
    get_ttg_from_ttt,
)
from jaclang.runtimelib.jacpim_static_analysis import JacPIMStaticCtx
from jaclang.runtimelib.jacpim_static_analysis.info_extract import extract_name


def get_walker_code(walker: WalkerArchetype) -> uni.Archetype:
    """Get the walker type code from walker instance."""
    for walker_code in JacPIMStaticCtx.get_jac_program().mod.get_all_sub_nodes(
        uni.Archetype
    ):
        if walker_code.get_all_sub_nodes(uni.Name)[0].value == extract_name(walker):
            return walker_code
    raise ValueError(f"Walker code for {walker} not found in program.")


class JacPIMMappingCtx:
    """JacPIM Mapping Phase global context."""

    mapping: dict[NodeArchetype, int] | None

    @classmethod
    def setter(cls, start_node: NodeArchetype, walker: WalkerArchetype) -> None:
        """Set all the values in the context."""
        static_ctx = JacPIMStaticCtx
        walker_code = get_walker_code(walker)
        get_ttg_from_ttt(
            get_access_pattern_single_walker(
                start_node, static_ctx.get_networkx(), walker_code
            )
        )
