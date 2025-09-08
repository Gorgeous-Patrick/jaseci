from jaclang.runtimelib.archetype import NodeAnchor, WalkerAnchor


class DPUMemoryContext():
    def __init__(self):
        self.node_memory: bytes = b""
        self.walker_memory: bytes = b"" # list of memory values per execution of a single DPU
        self.node_id_to_ptr: dict[int, int] = {}
        self.walker_id_to_ptr: dict[int, int] = {}
        self.current_execution_id: int = 0

    def download_nodes(self, node_id_to_stream: dict[int, bytes]):
        for node_id, node_stream in node_id_to_stream.items():
            self.node_id_to_ptr[node_id] = len(self.node_memory)
            assert len(node_stream) % 8 == 0
            self.node_memory += node_stream

    def get_node_ptr(self, node_id: int):
        return self.node_id_to_ptr[node_id]

    def change_node_value(self, node_id: int, node_stream: bytes):
        buf = bytearray(self.node_memory)
        ptr = self.node_id_to_ptr[node_id]
        buf[ptr:ptr+len(node_stream)] = node_stream
        self.node_memory = bytes(buf)

    def download_walkers(self, walker_id_to_stream: dict[int, bytes]):
        for walker_id, walker_stream in walker_id_to_stream.items():
            self.walker_id_to_ptr[walker_id] = len(self.walker_memory)
            assert len(walker_stream) % 8 == 0
            self.walker_memory += walker_stream

    def get_walker_ptr(self, walker_id: int):
        return self.walker_id_to_ptr[walker_id] + len(self.node_memory)

    def change_walker_value(self, walker_id: int, walker_stream: bytes):
        buf = bytearray(self.walker_memory[self.current_execution_id])
        ptr = self.walker_id_to_ptr[walker_id]
        buf[ptr:ptr+len(walker_stream)] = walker_stream
        self.walker_memory = bytes(buf)

    def dump_to_file(self, filename: str):
        with open(filename, "wb") as f:
            f.write(self.node_memory + self.walker_memory)

def get_memory_context(node_ids: list[int], all_nodes: list[NodeAnchor], walker: WalkerAnchor):
    context = DPUMemoryContext()
    node_id_to_stream = {node_id : all_nodes[node_id].archetype.get_byte_stream() for node_id in node_ids}
    context.download_nodes(node_id_to_stream)
    walker_id_to_stream = {0: walker.archetype.get_byte_stream()}
    context.download_walkers(walker_id_to_stream)
    return context
