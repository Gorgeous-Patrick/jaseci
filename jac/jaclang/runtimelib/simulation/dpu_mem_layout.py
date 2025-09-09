from jaclang.runtimelib.archetype import NodeAnchor, WalkerAnchor
from jaclang.runtimelib.simulation.upmem_codegen import MemoryRange


class DPUMemoryContext:
    def __init__(self):
        self.node_memory: bytes = b""
        self.walker_memory: bytes = (
            b""  # list of memory values per execution of a single DPU
        )
        self.node_id_to_range: dict[int, MemoryRange] = {}
        self.walker_id_to_range: dict[int, MemoryRange] = {}
        self.current_execution_id: int = 0

    def download_nodes(self, node_id_to_stream: dict[int, bytes]):
        for node_id, node_stream in node_id_to_stream.items():
            self.node_id_to_range[node_id] = MemoryRange(ptr=len(self.node_memory), size = len(node_stream))
            assert len(node_stream) % 8 == 0
            self.node_memory += node_stream

    def get_node_range(self, node_id: int) -> MemoryRange:
        return self.node_id_to_range[node_id]

    def change_node_stream(self, node_id: int, node_stream: bytes):
        buf = bytearray(self.node_memory)
        mem_range = self.node_id_to_range[node_id]
        ptr = mem_range.ptr
        assert mem_range.size == len(node_stream)
        buf[ptr : ptr + len(node_stream)] = node_stream
        self.node_memory = bytes(buf)

    def change_node_value(self, node_id: int, node: NodeAnchor):
        return self.change_node_stream(node_id, node.archetype.get_byte_stream())

    def max_node_size(self) -> int:
        return max([mem_range.size for mem_range in self.node_id_to_range.values()])

    def download_walkers(self, walker_id_to_stream: dict[int, bytes]):
        for walker_id, walker_stream in walker_id_to_stream.items():
            self.walker_id_to_range[walker_id] = MemoryRange(ptr=len(self.walker_memory) + len(self.node_memory), size = len(walker_stream))
            assert len(walker_stream) % 8 == 0
            self.walker_memory += walker_stream

    def get_walker_range(self, walker_id: int)-> MemoryRange:
        return self.walker_id_to_range[walker_id]

    def change_walker_stream(self, walker_id: int, walker_stream: bytes):
        buf = bytearray(self.walker_memory[self.current_execution_id])
        mem_range = self.walker_id_to_range[walker_id]
        ptr = mem_range.ptr - len(self.node_memory)
        assert mem_range.size == len(walker_stream)
        buf[ptr : ptr + len(walker_stream)] = walker_stream
        self.walker_memory = bytes(buf)

    def change_walker_value(self, walker_id: int, walker: WalkerAnchor):
        return self.change_walker_stream(walker_id, walker.archetype.get_byte_stream())

    def max_walker_size(self) -> int:
        return max([mem_range.size for mem_range in self.walker_id_to_range.values()])

    def dump_to_file(self, filename: str):
        with open(filename, "wb") as f:
            f.write(self.node_memory + self.walker_memory)


def get_memory_context(
    node_ids: list[int], all_nodes: list[NodeAnchor], walker: WalkerAnchor
):
    context = DPUMemoryContext()
    node_id_to_stream = {
        node_id: all_nodes[node_id].archetype.get_byte_stream() for node_id in node_ids
    }
    context.download_nodes(node_id_to_stream)
    walker_id_to_stream = {0: walker.archetype.get_byte_stream()}
    context.download_walkers(walker_id_to_stream)
    return context


def get_all_memory_contexts(
    mapping: dict[int, int], all_nodes: list[NodeAnchor], dpu_num: int
) -> list[DPUMemoryContext]:
    dpu_mem_contexts: list[DPUMemoryContext] = []
    for _ in range(dpu_num):
        dpu_mem_contexts.append(DPUMemoryContext())
    for node_id, dpu_id in mapping.items():
        dpu_mem_contexts[dpu_id].download_nodes(
            {node_id: all_nodes[node_id].archetype.get_byte_stream()}
        )
    return dpu_mem_contexts
