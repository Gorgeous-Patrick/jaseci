from jaclang.runtimelib.simulation.dpu_mem_layout import DPUMemoryContext
import copy


class Task:
    def __init__(self, dpu_id: int, start_mem_ctx: DPUMemoryContext):
        self.dpu_id = dpu_id
        self.trace = []
        self.start_mem_ctx = copy.deepcopy(start_mem_ctx)

    def add_node(self, node_id: int):
        self.trace.append(node_id)

    def save(self):
        print(f"Task ran through: {self.trace}")
        self.start_mem_ctx.dump_to_file(f"DPU{self.dpu_id}.bin")
