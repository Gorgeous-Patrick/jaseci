from dataclasses import dataclass


@dataclass
class TTG_Node:
  idx: int | None  # If it is None, it means this node represents the end of a path.
  conditional_next_nodes: list["TTG_Node"]
  parallel_next_nodes: list["TTG_Node"]


def print_ttg(node: TTG_Node):
  print("================")
  print_ttg_simple(node)

def print_ttg_simple(node, level=0):
    indent = "    " * level
    print(f"{indent}{node.idx}")
    for child in node.conditional_next_nodes + node.parallel_next_nodes:
        print_ttg_simple(child, level + 1)