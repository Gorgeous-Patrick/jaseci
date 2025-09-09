from jaclang.runtimelib.archetype import WalkerAnchor
from jaclang.runtimelib.simulation.dpu_mem_layout import DPUMemoryContext
import copy


class Task:
    TASK_COUNT = 0

    def __init__(
        self, dpu_id: int, start_mem_ctx: DPUMemoryContext, walker: WalkerAnchor
    ):
        self.task_id = Task.TASK_COUNT
        Task.TASK_COUNT += 1
        self.dpu_id: int = dpu_id
        self.trace: list[int] = []
        self.walker: WalkerAnchor = walker
        self.start_mem_ctx: DPUMemoryContext = copy.deepcopy(start_mem_ctx)

    def add_node(self, node_id: int):
        self.trace.append(node_id)

    def save(self):
        print(f"Task ran through: {self.trace}")
        self.start_mem_ctx.dump_to_file(f"task_bins/Task{self.task_id}.bin")
