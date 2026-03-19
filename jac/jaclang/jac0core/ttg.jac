"""TTG (Temporal Trace Graph) Generator.

Predicts walker traversal paths by analyzing the topology index stored
on root node anchors. Uses the existing TopologyIndex infrastructure
to resolve visit chains without loading archetype instances.

Visit type metadata is extracted lazily from the AST at runtime via
JacProgram.mod.hub, which holds the full deserialized AST for every
loaded module (backed by the JIR cache).
"""

import os;
import from dataclasses { dataclass, field }
import from uuid { UUID }
import from typing { Any }
import jaclang.jac0core.unitree as uni;
import from jaclang.jac0core.archetype { VisitType }
import from jaclang.jac0core.constant { Tokens as Tok }

"""State entry in the temporal trace graph."""
@dataclass
class TypedWalkerState {
    has walker_type: str,
        nd: UUID,
        depth: int,
        incoming_edge: (UUID | None) = None,
        children: list[TypedWalkerState] = field(default_factory=`list);
}

"""TTG Generator — predicts traversal paths using TopologyIndex.

Operates on the topology index stored on root node anchors.
No Jac archetype instances are loaded or populated.
"""
class JacTTGGenerator {
    @classmethod
    def _resolve_type_name(
        cls: type[JacTTGGenerator], ref: (type | str | None)
    ) -> (str | None);

    """Extract visit types from a walker's AST Archetype node at runtime.

    Walks the AST via JacProgram.mod.hub to find the walker's Archetype,
    then extracts (from_node_name, edge_type_name) from its abilities'
    EventSignatures and VisitStmts. Results are cached on the class as
    __jac_ttg_visits__ for subsequent calls.
    """
    @classmethod
    def _extract_visits_from_ast(
        cls: type[JacTTGGenerator], warch: Any
    ) -> list[VisitType];

    """Find the AST Archetype node for a given walker archetype class."""
    @classmethod
    def _find_walker_ast_node(
        cls: type[JacTTGGenerator], warch_cls: type
    ) -> (uni.Archetype | None);

    """Resolve a name to an Archetype AST node via symbol table lookup."""
    @classmethod
    def _resolve_archetype(
        cls: type[JacTTGGenerator], scope_src: uni.UniNode, name: str
    ) -> (uni.Archetype | None);

    @classmethod
    def get_ttg(
        cls: type[JacTTGGenerator], warch: Any, start_id: UUID, topology_index: Any
    ) -> tuple;

    @classmethod
    def get_prefetch_list(
        cls: type[JacTTGGenerator], start: UUID, ttg_children: dict
    ) -> list[UUID];
}
