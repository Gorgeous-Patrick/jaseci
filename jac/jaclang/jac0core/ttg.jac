"""TTG (Temporal Trace Graph) Generator.

Predicts walker traversal paths by analyzing the topology index stored
on root node anchors. Uses the existing TopologyIndex infrastructure
to resolve visit chains without loading archetype instances.

Visit type metadata is extracted lazily from the AST at runtime via
JacProgram.mod.hub, which holds the full deserialized AST for every
loaded module (backed by the JIR cache).
"""

import from uuid { UUID }
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.archetype { NodeAnchor, VisitType }
import from jaclang.jac0core.constant { Tokens as Tok }
import from jaclang.runtimelib.topology_index { TopologyIndex }

"""TTG Generator — predicts traversal paths using TopologyIndex.

Operates on the topology index stored on root node anchors.
No Jac archetype instances are loaded or populated.
"""
class JacTTGGenerator {
    @classmethod
    def _resolve_type_name(
        cls: type[JacTTGGenerator], ref: (type | str | None)
    ) -> (str | None);

    """Read a TTG support root without recording a tier-hit row."""
    @classmethod
    def _get_support_root_anchor(
        cls: type[JacTTGGenerator], mem: any, id: UUID
    ) -> (NodeAnchor | None);

    """Extract visit types from a walker's AST Archetype node at runtime.

    Walks the AST via JacProgram.mod.hub to find the walker's Archetype,
    then extracts (from_node_name, edge_type_name) from its abilities'
    EventSignatures and VisitStmts. Results are cached on the class as
    __jac_ttg_visits__ for subsequent calls.
    """
    @classmethod
    def _extract_visits_from_ast(
        cls: type[JacTTGGenerator], warch: any
    ) -> list[VisitType];

    """Find the AST Archetype node for a given walker archetype class."""
    @classmethod
    def _find_walker_ast_node(
        cls: type[JacTTGGenerator], warch_cls: type
    ) -> (uni.Archetype | None);

    """Resolve a name to an Archetype AST node via symbol table lookup."""
    @classmethod
    def _resolve_archetype(
        cls: type[JacTTGGenerator], scope_src: any, name: str
    ) -> (uni.Archetype | None);

    """Extract edge type and optional node filter from an AST node."""
    @classmethod
    def _extract_edge_step(
        cls: type[JacTTGGenerator], scope: any, item: any
    ) -> tuple[str | None, str | None, int];

    """Extract edge chains from an EdgeRefTrailer AST node."""
    @classmethod
    def _extract_chains_from_trailer(
        cls: type[JacTTGGenerator], scope: any, trailer: any
    ) -> list[tuple[str | None, str | None, int]];

    """Extract all edge chains from any AST body (ability, method, etc)."""
    @classmethod
    def _extract_refs_from_body(
        cls: type[JacTTGGenerator], body: any
    ) -> list[list[tuple[str | None, str | None, int]]];

    """Collect sub-nodes of `node_type` from an Ability, following the link
    to its separately-defined `impl` body (DeclImplMatchPass sets
    `ability.body = impl_def`, but `get_all_sub_nodes` doesn't descend
    into the ImplDef because it isn't in the ability's `kid` list).
    Same reason type_checker_pass line 594 does `self.traverse(nd.body)`
    for ImplDef bodies."""
    @classmethod
    def _ability_sub_nodes(
        cls: type[JacTTGGenerator], ability: uni.Ability, node_type: type
    ) -> list;

    """Extract a type name string from an AST type annotation expression."""
    @classmethod
    def _ast_type_name(
        cls: type[JacTTGGenerator], expr: (uni.UniNode | None)
    ) -> (str | None);

    """Resolve a function call target to its symbol when statically known."""
    @classmethod
    def _call_target_symbol(
        cls: type[JacTTGGenerator], call: uni.FuncCall
    ) -> (uni.Symbol | None);

    """Resolve a function call target to a Jac ability when statically known."""
    @classmethod
    def _resolve_called_ability(
        cls: type[JacTTGGenerator], call: uni.FuncCall
    ) -> (uni.Ability | None);

    """Infer the node type for a one-parameter helper like `f(n: Node)`."""
    @classmethod
    def _single_param_node_type(
        cls: type[JacTTGGenerator], ability: uni.Ability
    ) -> (str | None);

    """Trace FuncCall nodes in an ability body, resolve to Jac callees,
    and extract their refs expressions as VisitTypes."""
    @classmethod
    def _trace_method_calls(
        cls: type[JacTTGGenerator],
        ability: uni.Ability,
        current_node_type: (str | None) = None,
        seen: (set[int] | None) = None
    ) -> list[VisitType];

    @classmethod
    def get_ttg_prefetch_list(
        cls: type[JacTTGGenerator],
        warch: any,
        start_id: UUID,
        topology_index: TopologyIndex,
        mem: any = None,
        max_length: int = 200
    ) -> list[UUID];
}
