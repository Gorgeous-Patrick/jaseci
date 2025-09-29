"""Simulation context."""

from dataclasses import dataclass

from jaclang.runtimelib.jacpim_simulation_runtime.dpu_mem_layout import DPUMemoryCtx


class Task:
    """Task object that the DPU can run."""

    TASK_COUNT = 0

    def __init__(self, dpu_id: int, start_mem_ctx: DPUMemoryCtx) -> None:
        """Initialize the task to a certain memory context."""
        self.task_id = Task.TASK_COUNT
        Task.TASK_COUNT += 1
        self.dpu_id: int = dpu_id
        self.start_mem_ctx: DPUMemoryCtx = start_mem_ctx.clone()


@dataclass
class UPIMulatorExecutionMetaData:
    """Metadata for a single execution."""

    pass
