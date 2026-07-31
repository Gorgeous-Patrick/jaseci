"""TTG (Temporal Trace Graph) prefetch planning.

The generator predicts walker traversal paths from AST visit/ref patterns and
resolves those paths through the runtime topology index. It returns anchor IDs
that memory backends may prefetch before the walker executes.
"""

import from uuid { UUID }
import from typing { cast }

import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.archetype { VisitType }
import from jaclang.jac0core.constant { Tokens as Tok }

class JacTTGGenerator {
    @classmethod
    def _resolve_type_name(
        cls: type[JacTTGGenerator], ref: (type | str | None)
    ) -> (str | None);

    @classmethod
    def _find_walker_ast_node(
        cls: type[JacTTGGenerator], warch_cls: type
    ) -> (uni.Archetype | None);

    @classmethod
    def _resolve_archetype(
        cls: type[JacTTGGenerator], scope_src: uni.UniNode, name: str
    ) -> (uni.Archetype | None);

    @classmethod
    def _extract_edge_step(
        cls: type[JacTTGGenerator], scope: uni.UniNode, item: uni.UniNode
    ) -> tuple[str | None, str | None, int];

    @classmethod
    def _ability_sub_nodes(
        cls: type[JacTTGGenerator], ability: uni.Ability, node_type: type
    ) -> list[uni.UniNode];

    @classmethod
    def _extract_chains_from_trailer(
        cls: type[JacTTGGenerator], scope: uni.UniNode, trailer: uni.EdgeRefTrailer
    ) -> list[tuple[str | None, str | None, int]];

    @classmethod
    def _extract_refs_from_body(
        cls: type[JacTTGGenerator], body: uni.UniNode
    ) -> list[list[tuple[str | None, str | None, int]]];

    @classmethod
    def _trace_method_calls(
        cls: type[JacTTGGenerator], ability: uni.Ability
    ) -> list[VisitType];

    @classmethod
    def _extract_visits_from_ast(
        cls: type[JacTTGGenerator], warch: any
    ) -> list[VisitType];

    @classmethod
    def get_ttg_prefetch_list(
        cls: type[JacTTGGenerator],
        warch: any,
        start_id: UUID,
        topology_index: any,
        mem: any = None,
        max_length: int = 200
    ) -> list[UUID];
}
