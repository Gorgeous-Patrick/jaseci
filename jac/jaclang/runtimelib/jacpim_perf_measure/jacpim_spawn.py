"""Simple JacPIM Spawn Function - Direct spawn with DPU tracking.

This module provides a simple jacpim_spawn function that you can call directly
to execute walkers while harvesting DPU runtime information.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from jaclang.runtimelib.archetype import EdgeArchetype, NodeArchetype, WalkerArchetype
from jaclang.runtimelib.jacpim_mapping_analysis import JacPIMMappingCtx


@dataclass
class JacPIMIterationInfo:
    """Information about a JacPIM iteration."""

    iteration_number: int
    walkers_executed: List[tuple[WalkerArchetype, NodeArchetype, int]] = field(
        default_factory=list
    )  # walker, node, dpu
    start_time: float = field(default_factory=time.time)
    end_time: Optional[float] = None
    dpu_migrations: int = 0

    @property
    def duration(self) -> Optional[float]:
        """Get iteration duration in seconds."""
        if self.end_time is None:
            return None
        return self.end_time - self.start_time


class JacPIMExecutor:
    """Simple executor for JacPIM performance measurement."""

    def __init__(self, max_walkers_per_iteration: int = 8) -> None:
        """Initialize the executor.

        Args:
            max_walkers_per_iteration: Maximum number of walkers (K) per iteration
        """
        self.max_walkers_per_iteration = max_walkers_per_iteration
        self.current_iteration = 0
        self.active_walkers: List[WalkerArchetype] = []
        self.pending_walkers: List[WalkerArchetype] = []
        self.iteration_history: List[JacPIMIterationInfo] = []
        self.node_to_dpu_mapping: Dict[NodeArchetype, int] = {}

    def initialize_mapping(self, node: NodeArchetype, walker: WalkerArchetype) -> None:
        """Do nothing."""
        print("Using existing JacPIMMappingCtx mapping")

    def get_node_dpu(self, node: NodeArchetype) -> int:
        """Get the DPU core ID for a given node using the existing mapping."""
        # Use the already-set mapping from JacPIMMappingCtx
        partitioning = JacPIMMappingCtx.get_partitioning()

        # Get static context to find node index
        from jaclang.runtimelib.jacpim_static_analysis import JacPIMStaticCtx
        from jaclang.runtimelib.machine import JacMachine

        static_ctx = JacPIMStaticCtx()
        static_ctx.setter(JacMachine.get_context(), JacMachine.program)
        all_nodes = static_ctx.get_all_nodes()

        # Find the index of this node in the static context
        try:
            node_index = all_nodes.index(node)
        except ValueError:
            raise ValueError(f"Node {node} not found in static context")

        if node_index not in partitioning:
            raise ValueError(f"Node index {node_index} not mapped to any DPU")

        return partitioning[node_index]

    def add_walker(self, walker: WalkerArchetype, node: NodeArchetype) -> None:
        """Add walker to execution queue."""
        # Set walker's starting position
        walker.__jac__.next = [node.__jac__]

        if len(self.active_walkers) < self.max_walkers_per_iteration:
            self.active_walkers.append(walker)
        else:
            self.pending_walkers.append(walker)

    def run_iteration(self) -> JacPIMIterationInfo:
        """Execute one iteration of walkers."""
        iteration_info = JacPIMIterationInfo(iteration_number=self.current_iteration)

        # Move pending walkers to active (up to max_walkers_per_iteration)
        while (
            len(self.active_walkers) < self.max_walkers_per_iteration
            and self.pending_walkers
        ):
            self.active_walkers.append(self.pending_walkers.pop(0))

        # Execute each walker sequentially with DPU boundary detection
        for walker in self.active_walkers:
            # Get starting node from walker's next queue
            if not walker.__jac__.next:
                continue  # Skip walkers with no moves

            start_node_anchor = walker.__jac__.next[0]
            start_node = start_node_anchor.archetype

            # Only process if it's a node (skip edges for DPU calculation)
            if not isinstance(start_node, NodeArchetype):
                continue

            start_dpu = self.get_node_dpu(start_node)

            # Execute the walker with DPU-aware spawn (stops at DPU boundaries)
            final_node = self._dpu_aware_spawn_call(walker, start_node, start_dpu)

            # Record the execution (ensure we have a node for DPU mapping)
            result_node = (
                final_node if isinstance(final_node, NodeArchetype) else start_node
            )
            iteration_info.walkers_executed.append(
                (walker, result_node, self.get_node_dpu(result_node))
            )

            # If walker has more moves queued, it hit a DPU boundary - queue for next iteration
            if len(walker.__jac__.next) > 0:
                self.pending_walkers.append(walker)
                iteration_info.dpu_migrations += 1

        # Clear active walkers
        self.active_walkers.clear()

        # End iteration
        iteration_info.end_time = time.time()
        self.iteration_history.append(iteration_info)
        self.current_iteration += 1

        return iteration_info

    def run_all_iterations(self) -> Dict:
        """Run all pending iterations."""
        results = []

        while self.pending_walkers or self.active_walkers:
            iter_info = self.run_iteration()
            results.append(
                {
                    "iteration": iter_info.iteration_number,
                    "walkers_count": len(iter_info.walkers_executed),
                    "duration": iter_info.duration,
                    "dpu_migrations": iter_info.dpu_migrations,
                    "dpu_usage": self._get_dpu_usage(iter_info),
                }
            )

        return {"total_iterations": len(results), "iterations": results}

    def _dpu_aware_spawn_call(
        self, walker: WalkerArchetype, node: NodeArchetype, start_dpu: int
    ) -> NodeArchetype | EdgeArchetype:
        """DPU-aware spawn call that stops execution at DPU boundaries.

        Based on spawn_call but adds DPU boundary detection to preserve walker state.

        Args:
            walker: The walker to execute
            node: Starting node
            start_dpu: Starting DPU ID

        Returns:
            Final node where walker stopped
        """
        walker_anchor = walker.__jac__
        warch = walker_anchor.archetype

        # DO NOT reinitialize walker_anchor.next - it preserves state across multiple calls!
        # Only reset path for this iteration
        walker_anchor.path = []

        current_dpu = start_dpu

        # Main traversal loop with DPU boundary detection
        current_loc = node  # Default to starting node

        while len(walker_anchor.next):
            current_loc = walker_anchor.next.pop(0).archetype

            # DPU BOUNDARY CHECK - This is the key difference from regular spawn_call!
            if isinstance(current_loc, NodeArchetype):
                next_dpu = self.get_node_dpu(current_loc)
                if next_dpu != current_dpu:
                    # DPU boundary crossing detected - STOP and preserve walker state
                    print(f"DPU boundary crossing: DPU {current_dpu} -> DPU {next_dpu}")
                    # Put the node back in walker's next list (preserving walker state!)
                    walker_anchor.next.insert(0, current_loc.__jac__)
                    return (
                        walker_anchor.path[-1].archetype if walker_anchor.path else node
                    )

                current_dpu = next_dpu

            # Same DPU - continue execution (same as spawn_call)
            # walker ability with loc entry
            for i in warch._jac_entry_funcs_:
                if i.trigger and isinstance(current_loc, i.trigger):
                    i.func(warch, current_loc)
                if walker_anchor.disengaged:
                    return current_loc

            # loc ability with any entry
            for i in current_loc._jac_entry_funcs_:
                if not i.trigger:
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return current_loc

            # loc ability with walker entry
            for i in current_loc._jac_entry_funcs_:
                if i.trigger and isinstance(warch, i.trigger):
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return current_loc

            # loc ability with walker exit
            for i in current_loc._jac_exit_funcs_:
                if i.trigger and isinstance(warch, i.trigger):
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return current_loc

            # loc ability with any exit
            for i in current_loc._jac_exit_funcs_:
                if not i.trigger:
                    i.func(current_loc, warch)
                if walker_anchor.disengaged:
                    return current_loc

            # walker ability with loc exit
            for i in warch._jac_exit_funcs_:
                if i.trigger and isinstance(current_loc, i.trigger):
                    i.func(warch, current_loc)
                if walker_anchor.disengaged:
                    return current_loc

        # walker ability with any exit (final cleanup)
        for i in warch._jac_exit_funcs_:
            if not i.trigger:
                i.func(warch, current_loc)
            if walker_anchor.disengaged:
                return current_loc

        walker_anchor.ignores = []
        return current_loc

    def _get_dpu_usage(self, iteration_info: JacPIMIterationInfo) -> Dict[int, int]:
        """Get DPU usage for an iteration."""
        dpu_usage: dict[int, int] = {}
        for _, _, dpu_id in iteration_info.walkers_executed:
            dpu_usage[dpu_id] = dpu_usage.get(dpu_id, 0) + 1
        return dpu_usage


# Global executor instance
_executor = JacPIMExecutor()


def jacpim_spawn(
    walker: WalkerArchetype, node: NodeArchetype, execute_immediately: bool = True
) -> Any:  # noqa: ANN401
    """Spawn function - execute walker with DPU tracking.

    Args:
        walker: The walker to spawn
        node: Starting node
        execute_immediately: If True, execute immediately; if False, queue for batch execution

    Returns:
        Result of walker execution (if execute_immediately=True), otherwise None
    """
    global _executor  # noqa: F824

    # Initialize mapping if first call
    if not _executor.node_to_dpu_mapping:
        _executor.initialize_mapping(node, walker)

    if execute_immediately:
        # Add walker to executor and run all iterations to handle cross-DPU jumps
        _executor.add_walker(walker, node)

        # Run all iterations until no more walkers are pending
        all_results = _executor.run_all_iterations()

        return all_results
    else:
        # Queue for batch execution
        _executor.add_walker(walker, node)
        total_len = len(_executor.active_walkers) + len(_executor.pending_walkers)
        print(f"Queued walker for batch execution (total queued: {total_len})")
        return None


def jacpim_par_visit(
    old_walker: WalkerArchetype, new_walker: WalkerArchetype, target_node: NodeArchetype
) -> None:
    """Parallel Visit par_visit - queue new walker for next iteration.

    Args:
        old_walker: The walker calling par_visit
        new_walker: The new walker to spawn
        target_node: Target node for new walker
    """
    global _executor  # noqa: F824
    _executor.add_walker(new_walker, target_node)
    print(
        f"par_visit: Queued new walker for target node (parent walker: {id(old_walker)})"
    )


def jacpim_run_batch() -> Dict:
    """Execute all queued walkers in batches.

    Returns:
        Dictionary with batch execution results
    """
    global _executor  # noqa: F824
    return _executor.run_all_iterations()


def get_jacpim_stats() -> Dict:
    """Get JacPIM execution statistics.

    Returns:
        Dictionary with execution statistics
    """
    global _executor  # noqa: F824

    if not _executor.iteration_history:
        return {"message": "No executions recorded"}

    total_walkers = sum(
        len(iter_info.walkers_executed) for iter_info in _executor.iteration_history
    )
    avg_duration = sum(
        iter_info.duration or 0 for iter_info in _executor.iteration_history
    ) / len(_executor.iteration_history)

    # Calculate DPU usage
    dpu_usage_per_iteration = {}
    for iter_info in _executor.iteration_history:
        dpu_usage_per_iteration[iter_info.iteration_number] = _executor._get_dpu_usage(
            iter_info
        )

    return {
        "total_iterations": len(_executor.iteration_history),
        "total_walkers_executed": total_walkers,
        "average_iteration_duration": avg_duration,
        "dpu_usage_per_iteration": dpu_usage_per_iteration,
        "total_dpu_migrations": sum(
            iter_info.dpu_migrations for iter_info in _executor.iteration_history
        ),
    }
