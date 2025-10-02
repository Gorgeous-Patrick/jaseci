"""Memory layout generator."""

import copy

from jaclang.runtimelib.jacpim_mapping_analysis.data_mapper import DPU_NUM
from jaclang.runtimelib.jacpim_mapping_analysis.mapping_ctx import JacPIMMappingCtx
from jaclang.runtimelib.jacpim_perf_measure.cpu_run_ctx import JacPIMCPURunCtx
from jaclang.runtimelib.jacpim_simulation_runtime.dpu_data_structs import (
    Container,
    ContainerObject,
    Metadata,
)
from jaclang.runtimelib.jacpim_static_analysis.static_ctx import JacPIMStaticCtx

from .upmem_codegen import MemoryRange


class DPUObjMemoryCtx:
    """Memory layout generator for a single type of object."""

    def __init__(self) -> None:
        """Initialize an empty memory layout."""
        self.obj_memory: bytes = b""
        self.obj_id_to_range: dict[int, MemoryRange] = {}

    def download_obj(self, obj_id: int, obj_stream: bytes) -> None:
        """Add a new object to the memory layout."""
        self.obj_id_to_range[obj_id] = MemoryRange(
            ptr=len(self.obj_memory), size=len(obj_stream)
        )
        self.obj_memory += obj_stream

    def get_obj_range(self, obj_id: int) -> MemoryRange:
        """Get the range of a certain object."""
        return self.obj_id_to_range[obj_id]

    def change_obj_stream(self, obj_id: int, obj_stream: bytes) -> None:
        """Change the value of an object."""
        buf = bytearray(self.obj_memory)
        mem_range = self.obj_id_to_range[obj_id]
        ptr = mem_range.ptr
        assert mem_range.size == len(obj_stream)
        buf[ptr : ptr + len(obj_stream)] = obj_stream
        self.obj_memory = bytes(buf)

    def __len__(self) -> int:
        """Size of the mem."""
        return len(self.obj_memory)


class DPUMemoryCtx:
    """Generator for the entire memory layout."""

    def __init__(
        self,
        metadata_mem_ctx: DPUObjMemoryCtx,
        container_mem_ctx: DPUObjMemoryCtx,
        node_mem_ctx: DPUObjMemoryCtx,
        walker_mem_ctx: DPUObjMemoryCtx,
    ) -> None:
        """Initialize to combine all memory contexts."""
        self.metadata_mem_ctx = metadata_mem_ctx
        self.node_mem_ctx = node_mem_ctx
        self.walker_mem_ctx = walker_mem_ctx
        self.container_mem_ctx = container_mem_ctx

    def get_metadata_range(self) -> MemoryRange:
        """Get the metadata memory range."""
        return MemoryRange(0, len(self.metadata_mem_ctx))

    def get_node_range(self, node_id: int) -> MemoryRange:
        """Get the node memory range."""
        return self.node_mem_ctx.obj_id_to_range[node_id].add_offset(
            len(self.container_mem_ctx) + len(self.metadata_mem_ctx)
        )

    def get_walker_range(self, walker_id: int) -> MemoryRange:
        """Get the walker memory range."""
        return self.walker_mem_ctx.obj_id_to_range[walker_id].add_offset(
            len(self.container_mem_ctx)
            + len(self.node_mem_ctx)
            + len(self.metadata_mem_ctx)
        )

    def get_container_range(self, walker_id: int) -> MemoryRange:
        """Get the container memory range."""
        return self.container_mem_ctx.obj_id_to_range[walker_id].add_offset(
            len(self.metadata_mem_ctx)
        )

    def dump(self) -> bytes:
        """Sum up all the memory context contents."""
        return (
            self.node_mem_ctx.obj_memory
            + self.walker_mem_ctx.obj_memory
            + self.container_mem_ctx.obj_memory
        )

    def clone(self) -> "DPUMemoryCtx":
        """Deep copy the object."""
        return copy.deepcopy(self)


class DPUAllMemoryCtx:
    """Generator for all DPUs' memory layout."""

    # Initialize all DPUs' memory contexts (NUM_DPU)
    dpu_metadata_ctxs: list[DPUObjMemoryCtx] = [
        DPUObjMemoryCtx() for _ in range(DPU_NUM)
    ]
    dpu_node_ctxs: list[DPUObjMemoryCtx] = [DPUObjMemoryCtx() for _ in range(DPU_NUM)]
    dpu_walker_ctxs: list[DPUObjMemoryCtx] = [DPUObjMemoryCtx() for _ in range(DPU_NUM)]
    dpu_container_ctxs: list[DPUObjMemoryCtx] = [
        DPUObjMemoryCtx() for _ in range(DPU_NUM)
    ]

    @classmethod
    def node_snapshot_one_dpu(cls, dpu_id: int) -> DPUObjMemoryCtx:
        """Create a memory context for node snapshot."""
        node_mem_ctx = DPUObjMemoryCtx()
        for node_idx, node in enumerate(JacPIMStaticCtx.get_all_nodes()):
            if JacPIMMappingCtx.get_partitioning().get(node_idx) != dpu_id:
                continue
            node_mem_ctx.download_obj(node_idx, node.get_byte_stream())
        return node_mem_ctx

    @classmethod
    def node_snapshot_all_dpu(cls) -> list[DPUObjMemoryCtx]:
        """Create a memory context for node snapshot."""
        cls.dpu_node_ctxs = [
            cls.node_snapshot_one_dpu(dpu_id) for dpu_id in range(DPU_NUM)
        ]
        return cls.dpu_node_ctxs

    @classmethod
    def walker_snapshot_one_dpu(cls, dpu_id: int) -> DPUObjMemoryCtx:
        """Create a memory context for all active walkers on a DPU."""
        walker_mem_ctx = DPUObjMemoryCtx()
        for walker in JacPIMCPURunCtx.get_active_walkers()[dpu_id]:
            walker_id = JacPIMCPURunCtx.get_all_walkers().index(walker)
            walker_mem_ctx.download_obj(walker_id, walker.get_byte_stream())
        return walker_mem_ctx

    @classmethod
    def walker_snapshot_all_dpu(cls) -> list[DPUObjMemoryCtx]:
        """Create a memory context for all active walkers on all DPUs."""
        cls.dpu_walker_ctxs = [
            cls.walker_snapshot_one_dpu(dpu_id) for dpu_id in range(DPU_NUM)
        ]
        return cls.dpu_walker_ctxs

    @classmethod
    def container_snapshot_one_dpu(
        cls, dpu_id: int, walker_traces: dict[int, list[int]]
    ) -> DPUObjMemoryCtx:
        """Create a memory context for all containers on a DPU."""
        for walker_idx, walker_trace in walker_traces.items():
            if JacPIMMappingCtx.get_partitioning().get(walker_trace[0]) != dpu_id:
                continue
            container_objects: list[ContainerObject] = []
            walker = JacPIMCPURunCtx.get_all_walkers()[walker_idx]
            walker_id = JacPIMCPURunCtx.get_all_walkers().index(walker)
            walker_size = len(walker.get_byte_stream())
            for node_idx in walker_trace:
                node = JacPIMStaticCtx.get_all_nodes()[node_idx]
                node_size = len(node.get_byte_stream())
                edge_num = len(node.__jac__.edges)
                container_objects.append(
                    ContainerObject(
                        walker_ptr=cls.dpu_walker_ctxs[dpu_id]
                        .get_obj_range(walker_id)
                        .ptr,
                        walker_size=walker_size,
                        node_ptr=cls.dpu_node_ctxs[dpu_id].get_obj_range(node_idx).ptr,
                        node_size=node_size,
                        edge_num=edge_num,
                    )
                )
                cls.dpu_container_ctxs[dpu_id].download_obj(
                    walker_id, Container(container_objects).get_byte_stream()
                )

        return cls.dpu_container_ctxs[dpu_id]

    @classmethod
    def container_snapshot_all_dpu(
        cls, walker_traces: dict[int, list[int]]
    ) -> list[DPUObjMemoryCtx]:
        """Create a memory context for all containers on all DPUs."""
        cls.dpu_container_ctxs = [
            cls.container_snapshot_one_dpu(dpu_id, walker_traces)
            for dpu_id in range(DPU_NUM)
        ]
        return cls.dpu_container_ctxs

    @classmethod
    def metadata_snapshot_one_dpu(cls, dpu_id: int) -> DPUObjMemoryCtx:
        """Create a memory context for metadata on a DPU."""
        metadata = Metadata(
            walker_num=0,  # to be filled later
            walker_container_ptrs=[],  # to be filled later
            extra_mram_space_ptr=0,  # to be filled later
        )
        extra_mram_space_ptr = (
            len(metadata.get_byte_stream())
            + len(cls.dpu_node_ctxs[dpu_id])
            + len(cls.dpu_walker_ctxs[dpu_id])
            + len(cls.dpu_container_ctxs[dpu_id])
        )
        mem_ctx = DPUMemoryCtx(
            metadata_mem_ctx=DPUObjMemoryCtx(),
            node_mem_ctx=cls.dpu_node_ctxs[dpu_id],
            walker_mem_ctx=cls.dpu_walker_ctxs[dpu_id],
            container_mem_ctx=cls.dpu_container_ctxs[dpu_id],
        )
        metadata.extra_mram_space_ptr = extra_mram_space_ptr
        metadata.walker_num = len(JacPIMCPURunCtx.get_active_walkers()[dpu_id])
        metadata.walker_container_ptrs = [
            mem_ctx.get_container_range(
                JacPIMCPURunCtx.get_all_walkers().index(walker)
            ).ptr
            for walker in JacPIMCPURunCtx.get_active_walkers()[dpu_id]
        ]
        metadata_mem_ctx = DPUObjMemoryCtx()
        metadata_mem_ctx.download_obj(0, metadata.get_byte_stream())
        return metadata_mem_ctx

    @classmethod
    def metadata_snapshot_all_dpu(cls) -> list[DPUObjMemoryCtx]:
        """Create a memory context for metadata on all DPUs."""
        cls.dpu_metadata_ctxs = [
            cls.metadata_snapshot_one_dpu(dpu_id) for dpu_id in range(DPU_NUM)
        ]
        return cls.dpu_metadata_ctxs

    @classmethod
    def start_running(cls) -> None:
        """Snapshot nodes and walkers for all DPUs."""
        # Clear previous memory contexts
        cls.dpu_node_ctxs = [DPUObjMemoryCtx() for _ in range(DPU_NUM)]
        cls.dpu_walker_ctxs = [DPUObjMemoryCtx() for _ in range(DPU_NUM)]
        cls.dpu_metadata_ctxs = [DPUObjMemoryCtx() for _ in range(DPU_NUM)]
        cls.dpu_container_ctxs = [DPUObjMemoryCtx() for _ in range(DPU_NUM)]

        cls.node_snapshot_all_dpu()
        cls.walker_snapshot_all_dpu()

    @classmethod
    def finish_running(cls, walker_traces: dict[int, list[int]]) -> list[DPUMemoryCtx]:
        """Snapshot containers and metadata for all DPUs."""
        cls.container_snapshot_all_dpu(walker_traces)
        cls.metadata_snapshot_all_dpu()
        return [
            DPUMemoryCtx(
                metadata_mem_ctx=cls.dpu_metadata_ctxs[dpu_id],
                node_mem_ctx=cls.dpu_node_ctxs[dpu_id],
                walker_mem_ctx=cls.dpu_walker_ctxs[dpu_id],
                container_mem_ctx=cls.dpu_container_ctxs[dpu_id],
            )
            for dpu_id in range(DPU_NUM)
        ]
