"""CPU-based execution context for JacPIM walkers, managing their lifecycle and DPU boundary crossings."""

from jaclang.runtimelib.archetype import (
    EdgeAnchor,
    NodeAnchor,
    NodeArchetype,
    WalkerArchetype,
)
from jaclang.runtimelib.jacpim_mapping_analysis import JacPIMMappingCtx
from jaclang.runtimelib.jacpim_mapping_analysis.data_mapper import DPU_NUM
from jaclang.runtimelib.jacpim_simulation_runtime.dpu_data_structs import (
    Container,
    ContainerObject,
    MAX_DPU_THREAD_NUM,
    Metadata,
)
from jaclang.runtimelib.jacpim_simulation_runtime.dpu_mem_layout import (
    DPUMemoryCtx,
    DPUObjMemoryCtx,
)
from jaclang.runtimelib.jacpim_static_analysis.static_ctx import JacPIMStaticCtx


class JacPIMCPURunCtx:
    """CPU-based execution context for JacPIM walkers."""

    pending_walkers: list[WalkerArchetype] = []
    active_walkers: list[list[WalkerArchetype]] | None = None
    all_walkers: list[WalkerArchetype] = []

    @classmethod
    def setter(cls) -> None:
        """Initialize the CPU run context."""
        cls.pending_walkers = []
        cls.active_walkers = []
        for _ in range(DPU_NUM):
            cls.active_walkers.append([])

    @classmethod
    def add_pending_walker(
        cls, walker: WalkerArchetype, start_node: NodeArchetype
    ) -> None:
        """Add a walker to the pending list."""
        walker.__jac__.next = [start_node.__jac__]
        cls.pending_walkers.append(walker)
        cls.all_walkers.append(walker)

    @classmethod
    def get_pending_nodes_and_walkers(
        cls,
    ) -> list[tuple[NodeArchetype, WalkerArchetype]]:
        """Get the list of pending walkers along with their start nodes."""
        result = []
        for walker in cls.pending_walkers:
            if len(walker.__jac__.next) == 0:
                raise RuntimeError("Walker has no next node to visit.")
            start_node = walker.__jac__.next[0]
            if isinstance(start_node, EdgeAnchor):
                start_node = start_node.target
            if not isinstance(start_node, NodeAnchor):
                raise RuntimeError("Start node is not a NodeAnchor.")
            result.append((start_node.archetype, walker))
        return result

    @classmethod
    def get_active_walkers(cls) -> list[list[WalkerArchetype]]:
        """Get the list of active walkers per DPU."""
        if cls.active_walkers is None:
            raise RuntimeError("Active walkers not initialized.")
        return cls.active_walkers

    @classmethod
    def set_pending_walkers_to_active(cls) -> None:
        """Move pending walkers to active walkers if there is space in the target DPU."""
        new_pending_walkers: list[WalkerArchetype] = []
        for walker in cls.pending_walkers:
            if len(walker.__jac__.next) == 0:
                raise RuntimeError("Walker has no next node to visit.")
            start_node = walker.__jac__.next[0]
            if isinstance(start_node, EdgeAnchor):
                start_node = start_node.target
            start_node_idx = JacPIMStaticCtx.get_all_nodes().index(start_node.archetype)
            dpu_id = JacPIMMappingCtx.get_partitioning().get(start_node_idx)
            if dpu_id is None:
                raise RuntimeError("DPU ID not found for node.")
            if len(cls.get_active_walkers()[dpu_id]) >= MAX_DPU_THREAD_NUM:
                new_pending_walkers.append(walker)
                continue
            cls.get_active_walkers()[dpu_id].append(walker)
        cls.pending_walkers = new_pending_walkers

    @classmethod
    def run_one_walker(cls, walker: WalkerArchetype) -> bool:
        """
        Run one walker until completion or DPU boundary.

        Return True if walker is done (nothing is left to visit).
        Return False if the walker wants to jump to another DPU.
        """
        walker_anchor = walker.__jac__
        warch = walker_anchor.archetype

        # Get static context and partitioning once
        all_nodes = JacPIMStaticCtx.get_all_nodes()
        partitioning = JacPIMMappingCtx.get_partitioning()

        # Determine current DPU
        current_dpu = None

        # Main execution loop - continue until done or DPU boundary
        while walker_anchor.next and len(walker_anchor.next) > 0:

            # Get the next location
            next_anchor = walker_anchor.next[0]
            if isinstance(next_anchor, EdgeAnchor):
                next_anchor = next_anchor.target

            next_node = next_anchor.archetype

            # Check if it's a valid node
            if not isinstance(next_node, NodeArchetype):
                # Skip non-node archetypes
                walker_anchor.next.pop(0)
                continue

            # Get DPU mapping for next node
            try:
                next_node_idx = all_nodes.index(next_node)
                target_dpu = partitioning.get(next_node_idx)

                if target_dpu is None:
                    raise RuntimeError(
                        f"Node index {next_node_idx} not mapped to any DPU"
                    )

            except ValueError:
                raise RuntimeError(f"Node {next_node} not found in static context")

            # Determine current DPU if not set yet
            if current_dpu is None:
                current_dpu = target_dpu  # First move

            # DPU BOUNDARY CHECK
            if target_dpu != current_dpu:
                # Walker wants to cross DPU boundary - stop here
                return False

            # Same DPU - execute one step
            # Pop the next location and process it
            current_loc = walker_anchor.next.pop(0).archetype
            current_node = (
                current_loc
                if isinstance(current_loc, NodeArchetype)
                else current_loc.__jac__.target.archetype
            )
            current_node_idx = all_nodes.index(current_node)
            walker_idx = cls.all_walkers.index(walker)
            # Log the visit
            DPUAllMemoryCtx.record_walker_trace(walker_idx, current_node_idx)

            # Execute walker abilities on this location (same pattern as spawn_call)
            # walker ability with loc entry
            for i in warch._jac_entry_funcs_:
                if i.trigger and isinstance(current_loc, i.trigger):
                    i.func(warch, current_loc)
                if walker_anchor.disengaged:
                    return True  # Walker is done

            # loc ability with any entry
            for i in current_loc._jac_entry_funcs_:
                if not i.trigger:
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return True  # Walker is done

            # loc ability with walker entry
            for i in current_loc._jac_entry_funcs_:
                if i.trigger and isinstance(warch, i.trigger):
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return True  # Walker is done

            # loc ability with walker exit
            for i in current_loc._jac_exit_funcs_:
                if i.trigger and isinstance(warch, i.trigger):
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return True  # Walker is done

            # loc ability with any exit
            for i in current_loc._jac_exit_funcs_:
                if not i.trigger:
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return True  # Walker is done

            # walker ability with loc exit
            for i in warch._jac_exit_funcs_:
                if i.trigger and isinstance(current_loc, i.trigger):
                    i.func(warch, current_loc)
                if walker_anchor.disengaged:
                    return True  # Walker is done

        # Walker has no more moves - it's done
        return True

    @classmethod
    def run_all_active_walkers(cls) -> None:
        """
        Run all active walkers once.

        If a walker wants to jump to another DPU, it will be moved to the pending list.
        A walker that finishes will be removed.
        """
        print("DEBUG: One round of running all active walkers")
        active_walkers = cls.get_active_walkers()
        DPUAllMemoryCtx.start_running()
        for dpu_id in range(DPU_NUM):
            for walker in active_walkers[dpu_id]:
                is_done = cls.run_one_walker(walker)
                if not is_done:
                    # Move to pending list
                    cls.pending_walkers.append(walker)
            # A walker is either done or moved to pending - clear active list
        DPUAllMemoryCtx.finish_running()
        for dpu_id in range(DPU_NUM):
            active_walkers[dpu_id] = []

    @classmethod
    def has_pending_walkers(cls) -> bool:
        """Check if there are pending walkers."""
        return len(cls.pending_walkers) > 0

    @classmethod
    def has_active_walkers(cls) -> bool:
        """Check if there are active walkers."""
        return any(len(dpu_walkers) > 0 for dpu_walkers in cls.get_active_walkers())

    @classmethod
    def run_until_all_done(cls) -> None:
        """Run until all walkers are done."""
        while cls.has_pending_walkers() or cls.has_active_walkers():
            cls.set_pending_walkers_to_active()
            cls.run_all_active_walkers()

    @classmethod
    def get_all_active_walkers(cls) -> list[WalkerArchetype]:
        """Get a flat list of all active walkers across all DPUs."""
        if cls.active_walkers is None:
            raise RuntimeError("Active walkers not initialized.")
        all_active = []
        for dpu_walkers in cls.active_walkers:
            all_active.extend(dpu_walkers)
        return all_active

    @classmethod
    def get_all_walkers(cls) -> list[WalkerArchetype]:
        """Get a list of all walkers that have been added to the context."""
        return cls.all_walkers


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
    walker_traces: dict[int, list[int]] = {}
    all_memory_dumps: list[list[DPUMemoryCtx]] = []

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
            trace_lengths=[],  # to be filled later
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
        metadata.trace_lengths = [
            len(cls.walker_traces[JacPIMCPURunCtx.get_all_walkers().index(walker_arch)])
            for walker_arch in JacPIMCPURunCtx.get_active_walkers()[dpu_id]
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
        cls.walker_traces = {}

        cls.node_snapshot_all_dpu()
        cls.walker_snapshot_all_dpu()

    @classmethod
    def record_walker_trace(cls, walker_id: int, node_idx: int) -> None:
        """Record the trace of a walker visiting nodes."""
        if walker_id not in cls.walker_traces:
            cls.walker_traces[walker_id] = []
        # print(f"DEBUG: Recording walker {walker_id} visiting node {node_idx}")
        cls.walker_traces[walker_id].append(node_idx)

    @classmethod
    def finish_running(cls) -> list[DPUMemoryCtx]:
        """Snapshot containers and metadata for all DPUs."""
        cls.container_snapshot_all_dpu(cls.walker_traces)
        cls.metadata_snapshot_all_dpu()
        res = [
            DPUMemoryCtx(
                metadata_mem_ctx=cls.dpu_metadata_ctxs[dpu_id],
                node_mem_ctx=cls.dpu_node_ctxs[dpu_id],
                walker_mem_ctx=cls.dpu_walker_ctxs[dpu_id],
                container_mem_ctx=cls.dpu_container_ctxs[dpu_id],
            ).clone()
            for dpu_id in range(DPU_NUM)
        ]
        cls.all_memory_dumps.append(res)
        return res
