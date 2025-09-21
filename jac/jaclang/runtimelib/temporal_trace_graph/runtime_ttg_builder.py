from jaclang.runtimelib.simulation.task import TaskMgr
from jaclang.runtimelib.temporal_trace_graph.ttg_node import TTG_Node


class RuntimeTTGBuilder:
  def __init__(self, start_node_idx: int):
    self.root_ttg = TTG_Node(idx=start_node_idx, conditional_next_nodes=[], parallel_next_nodes=[])
    self.walker_states = [self.root_ttg]
    self.task_mgr = TaskMgr()
  
  def add_next_sync_node(self, walker_idx: int, next_node_idx: int):
    new_ttg_node = TTG_Node(idx=next_node_idx, conditional_next_nodes=[], parallel_next_nodes=[])
    self.walker_states[walker_idx].conditional_next_nodes.append(new_ttg_node)
    self.walker_states[walker_idx] = new_ttg_node
  
  def add_next_async_node(self, walker_idx: int, next_node_idx: int) -> int:
    new_ttg_node = TTG_Node(idx=next_node_idx, conditional_next_nodes=[], parallel_next_nodes=[])
    self.walker_states[walker_idx].parallel_next_nodes.append(new_ttg_node)
    # Get a new walker
    self.walker_states.append(new_ttg_node)
    return len(self.walker_states) - 1  # Return the new walker index
  
  def generate_tasks(self, mapping: dict[int, int]) -> list[tuple[int, int]]:
    """Chunk the ttg into tasks based on the mapping. All ttg nodes inside a task should be mapped to the same DPU and have no parallel edges."""

    def traverse_one_thread(ttg_node: TTG_Node, mapping: dict[int, int]) -> tuple[list[int], list[TTG_Node]]:
      if (ttg_node.idx is None):
        return [], []
      current_dpu = mapping[ttg_node.idx]
      path = [ttg_node.idx]
      while len(ttg_node.parallel_next_nodes) == 0:
        if len(ttg_node.conditional_next_nodes) == 0:
          return path, []
        assert len(ttg_node.conditional_next_nodes) == 1
        next_node = ttg_node.conditional_next_nodes[0]
        if next_node.idx is None or mapping[next_node.idx] != current_dpu:
          return path, [next_node]
        path.append(next_node.idx)
        ttg_node = next_node
      return path, ttg_node.parallel_next_nodes
    
    return tasks
