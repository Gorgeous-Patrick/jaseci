from jaclang.runtimelib.archetype import WalkerAnchor
from .dpu_mem_layout import DPUMemoryContext
from .upmem_codegen import CodeGenContext
from jaclang.runtimelib.constructs import NodeAnchor


class DPUSessionContext():
    def __init__(self, all_nodes: list[NodeAnchor], all_walkers: list[WalkerAnchor]):
        self.all_nodes = all_nodes
        self.all_walkers = all_walkers
        node_id_to_stream = {idx: node.get_byte_stream() for idx, node in enumerate(all_nodes)}
        walker_id_to_stream = {idx: walker.get_byte_stream() for idx, walker in enumerate(all_walkers)}
        self.memory_context_before_run = DPUMemoryContext()
        self.memory_context_before_run.download_nodes(node_id_to_stream)
        self.memory_context_before_run.download_walkers(walker_id_to_stream)

    def walker_run_on(self, walker: WalkerAnchor, nodes: list[NodeAnchor]):
        code_gen_context = CodeGenContext()
