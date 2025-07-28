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

def get_visit_sequences(ability: uni.Ability) -> Generator[list[uni.UniCFGNode]]:
    print(ability.printgraph())
    print("=========")
    stack: list[_TracingInfo] = [[ability]]
    while (len(stack) > 0):
        path = stack.pop()
        node = path[-1]
        new_nodes = [new_node for new_node in node.bb_out if new_node not in path]
        new_paths = [path + [new_node] for new_node in new_nodes]
        for new_path in new_paths:
            new_node = new_path[-1]
            if len(new_node.bb_out) == 0:
                yield new_path
            else:
                stack.append(new_path)
    
