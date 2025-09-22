import os
from jaclang.runtimelib.archetype import EdgeAnchor, NodeAnchor, WalkerArchetype
from dataclasses import dataclass
from jaclang.runtimelib.data_mapper.partitioner import DPU_NUM, random_partition, round_robin_partition
from jaclang.runtimelib.simulation.dpu_mem_layout import DPUMemoryContext, get_all_memory_contexts
from jaclang.runtimelib.temporal_trace_graph import get_access_pattern_single_walker
from jaclang.runtimelib.temporal_trace_graph.access_pattern import get_paths_from_ttg
import networkx as nx
import jaclang.compiler.unitree as uni
from jaclang.runtimelib.simulation.task import Task, TaskMgr


@dataclass 
class JacPIMCtx:
  mapping: dict[int, int]
  all_nodes: list[NodeAnchor]
  all_edges: list[EdgeAnchor]
  start_node: NodeAnchor
  mem_ctxs: list[DPUMemoryContext]
  walker_num: int = 0
  task_manager: TaskMgr = TaskMgr()

class JacPIMCtxMgr:
  ctx: JacPIMCtx | None = None
  @classmethod
  def create_ctx(cls, all_nodes: list[NodeAnchor], all_edges: list[EdgeAnchor], start_node: NodeAnchor, graph: nx.DiGraph, walker_code: uni.Archetype) -> JacPIMCtx:
      node_idx = all_nodes.index(start_node)

      traversal_path = get_paths_from_ttg(get_access_pattern_single_walker(
          start_idx=node_idx,
          network=graph,
          walker_type=walker_code,
      ))
      # print("Traversal Path Sample:", [[all_nodes[i].archetype for i in path] for path in traversal_path])

      random_mapping = random_partition(traversal_path, graph)
      rounding_mapping = round_robin_partition(traversal_path, graph)

      MAPPING = os.environ.get("MAPPING")
      if MAPPING is None:
          raise ValueError("MAPPING environment variable not set")
      elif MAPPING == "random":
          mapping = random_mapping
      elif MAPPING == "rounding":
          mapping = rounding_mapping
      mem_contexts = get_all_memory_contexts(mapping, all_nodes, DPU_NUM)
      ctx = JacPIMCtx(mapping, all_nodes, all_edges, start_node, mem_contexts)
      cls.ctx = ctx
      return ctx

  @classmethod
  def created(cls) -> bool:
    return cls.ctx is not None
  
  @classmethod
  def get_ctx(cls) -> JacPIMCtx:
    if cls.ctx is None:
      raise ValueError("JacPIMCtx not created yet")
    return cls.ctx