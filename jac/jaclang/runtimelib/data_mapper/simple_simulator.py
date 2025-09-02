import jaclang.compiler.unitree as uni
import networkx as nx
def num_cycles(ability: uni.Ability) -> int:
  # Count the number of instructions per ability
  container: list[tuple[uni.UniCFGNode, int]] = [(ability, 0)]
  max_depth = 0
  while len(container) > 0:
    curr, depth = container.pop()
    max_depth = max(max_depth, depth)
    for child in curr.bb_out:
      container.append((child, depth + 1))
  return max_depth

def get_total_number_cycles(trace: list[int], network: nx.DiGraph, abilities: dict[str, uni.Ability]) -> int:
    total_cycle = 0
    for i in trace:
       node_type = network.nodes[i].get("node_type")
       ability = abilities.get(node_type)
       if ability:
           total_cycle += num_cycles(ability)
    return total_cycle