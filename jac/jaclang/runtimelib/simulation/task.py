from jaclang.runtimelib.archetype import WalkerAnchor
from jaclang.runtimelib.simulation.dpu_mem_layout import DPUMemoryContext
from jaclang.runtimelib.data_mapper.partitioner import DPU_NUM
import copy
from typing import Dict, List, Set, Optional, Any
from collections import defaultdict, deque


class Task:
    TASK_COUNT = 0

    def __init__(
        self, dpu_id: int, start_mem_ctx: DPUMemoryContext
    ):
        self.task_id = Task.TASK_COUNT
        Task.TASK_COUNT += 1
        self.dpu_id: int = dpu_id
        self.trace: list[int] = []
        self.start_mem_ctx: DPUMemoryContext = copy.deepcopy(start_mem_ctx)

    def add_node(self, node_id: int):
        self.trace.append(node_id)

    def save(self):
        print(f"Task ran through: {self.trace}")
        self.start_mem_ctx.dump_to_file(f"task_bins/Task{self.task_id}.bin")

DPU_THREAD_NUM = 12  # Number of threads (walkers) that can run parallely on a DPU.

class TaskSet:
    TASK_SET_COUNT = 0
    # A list of walkers running parallely on the same DPU.
    def __init__(self, dpu_id: int):
        self.dpu_id = dpu_id
        self.tasks: list[Task] = []
        self.mem_ctx: Optional[DPUMemoryContext] = None
        self.task_set_id = TaskSet.TASK_SET_COUNT
        TaskSet.TASK_SET_COUNT += 1

    def add_task(self, task: Task):
        assert task.dpu_id == self.dpu_id
        assert len(self.tasks) < DPU_THREAD_NUM
        self.tasks.append(task)
        if self.mem_ctx is None:
            self.mem_ctx = copy.deepcopy(task.start_mem_ctx)
        else:
            self.mem_ctx.merge(task.start_mem_ctx)
    
    def get_mem_ctx(self) -> DPUMemoryContext:
        if self.mem_ctx is None:
            raise ValueError("No memory context available, no tasks added yet.")
        return self.mem_ctx


class TaskMgr:
    """Task Manager for scheduling tasks across DPUs with dependencies."""
    
    def __init__(self):
        self.tasks: Dict[int, Task] = {}  # task_id -> Task
        self.dependencies: Dict[int, int] = {}  # task_id -> dependency_task_id
        self.reverse_dependencies: Dict[int, Set[int]] = defaultdict(set)  # task_id -> set of tasks that depend on it
        self.scheduled_tasks: Set[int] = set()  # Tasks that have been scheduled
        self.ready_to_schedule: Set[int] = set()  # Tasks ready to be scheduled (dependencies met)
        
        # Scheduling rounds - list of TaskSets for each round
        self.scheduling_rounds: List[List[TaskSet]] = []
        self.current_round: int = 0
        
    def add_task(self, task: Task, dependency_task_id: Optional[int] = None) -> int:
        """
        Add a task to the manager.
        
        Args:
            task: The task to add
            dependency_task_id: Optional task_id that this task depends on
            
        Returns:
            The task_id of the added task
        """
        task_id = task.task_id
        self.tasks[task_id] = task
        print(f"DEBUG TaskMgr: Adding task {task_id} (DPU {task.dpu_id}) with dependency {dependency_task_id}")
        
        if dependency_task_id is not None:
            if dependency_task_id not in self.tasks:
                raise ValueError(f"Dependency task {dependency_task_id} not found")
            self.dependencies[task_id] = dependency_task_id
            self.reverse_dependencies[dependency_task_id].add(task_id)
            print(f"DEBUG TaskMgr: Task {task_id} depends on task {dependency_task_id}")
        else:
            # No dependency, task is immediately ready to schedule
            self.ready_to_schedule.add(task_id)
            print(f"DEBUG TaskMgr: Task {task_id} is ready to schedule (no dependency)")
            
        return task_id
    
    def get_ready_tasks(self) -> Set[int]:
        """Get tasks that are ready to be scheduled (dependencies satisfied)."""
        return self.ready_to_schedule.copy()
    
    def mark_task_scheduled(self, task_id: int):
        """Mark a task as scheduled and update dependent tasks."""
        if task_id not in self.ready_to_schedule:
            raise ValueError(f"Task {task_id} is not ready to schedule")
            
        # Remove from ready to schedule
        self.ready_to_schedule.remove(task_id)
        self.scheduled_tasks.add(task_id)
        
        # Check if any dependent tasks are now ready for FUTURE rounds
        for dependent_task_id in self.reverse_dependencies[task_id]:
            if dependent_task_id not in self.scheduled_tasks:
                # Check if all dependencies are satisfied
                if dependent_task_id in self.dependencies:
                    dependency_id = self.dependencies[dependent_task_id]
                    if dependency_id in self.scheduled_tasks:
                        # Don't add to ready_to_schedule yet - this will be handled
                        # at the end of the current round
                        pass
                else:
                    # No dependencies, should already be ready
                    self.ready_to_schedule.add(dependent_task_id)
    
    def complete_round(self):
        """Complete the current round and make dependent tasks ready for next round."""
        # Find all tasks that can now be scheduled because their dependencies are complete
        newly_ready = []
        for task_id, task in self.tasks.items():
            if (task_id not in self.scheduled_tasks and 
                task_id not in self.ready_to_schedule and
                task_id in self.dependencies):
                
                dependency_id = self.dependencies[task_id]
                if dependency_id in self.scheduled_tasks:
                    newly_ready.append(task_id)
        
        # Add newly ready tasks for the next round
        for task_id in newly_ready:
            self.ready_to_schedule.add(task_id)
    
    def create_scheduling_round(self) -> List[TaskSet]:
        """
        Create a new scheduling round with tasks that can be scheduled in parallel.
        
        Returns:
            List of TaskSets for each DPU for this round
        """
        round_tasksets = [TaskSet(i) for i in range(DPU_NUM)]
        scheduled_in_round = []
        
        # Group ready tasks by DPU
        tasks_by_dpu: Dict[int, List[int]] = defaultdict(list)
        for task_id in self.ready_to_schedule:
            task = self.tasks[task_id]
            tasks_by_dpu[task.dpu_id].append(task_id)
        
        # Schedule tasks to DPUs respecting thread limits
        for dpu_id, task_ids in tasks_by_dpu.items():
            for task_id in task_ids[:DPU_THREAD_NUM]:  # Limit to DPU capacity
                task = self.tasks[task_id]
                round_tasksets[dpu_id].add_task(task)
                scheduled_in_round.append(task_id)
        
        # Mark scheduled tasks
        for task_id in scheduled_in_round:
            self.mark_task_scheduled(task_id)
        
        # Complete the round and prepare dependent tasks for next round
        self.complete_round()
        
        self.scheduling_rounds.append(round_tasksets)
        return round_tasksets
    
    def schedule_all_tasks(self) -> List[List[TaskSet]]:
        """
        Schedule all tasks into rounds, respecting dependencies and DPU constraints.
        
        Returns:
            List of scheduling rounds, each containing TaskSets for each DPU
        """
        print(f"DEBUG TaskMgr: Starting scheduling with {len(self.tasks)} tasks")
        print(f"DEBUG TaskMgr: Dependencies: {self.dependencies}")
        print(f"DEBUG TaskMgr: Ready to schedule: {self.ready_to_schedule}")
        
        while self.has_tasks_to_schedule():
            print(f"DEBUG TaskMgr: Creating round {len(self.scheduling_rounds)}")
            round_tasksets = self.create_scheduling_round()
            # If no tasks were scheduled in this round but we still have tasks,
            # there might be a circular dependency or other issue
            if not any(len(ts.tasks) > 0 for ts in round_tasksets):
                remaining_tasks = list(self.ready_to_schedule)
                raise RuntimeError(f"Cannot schedule remaining tasks: {remaining_tasks}. "
                                 "Check for circular dependencies.")
        
        print(f"DEBUG TaskMgr: Finished scheduling, created {len(self.scheduling_rounds)} rounds")
        return self.scheduling_rounds
    
    def has_tasks_to_schedule(self) -> bool:
        """Check if there are any tasks that haven't been scheduled yet."""
        return len(self.ready_to_schedule) > 0
    
    def get_task_status(self) -> Dict[str, int]:
        """Get current status of tasks."""
        return {
            "ready_to_schedule": len(self.ready_to_schedule),
            "scheduled": len(self.scheduled_tasks),
            "total": len(self.tasks),
            "rounds": len(self.scheduling_rounds)
        }
    
    def get_scheduling_plan(self) -> List[Dict[str, Any]]:
        """
        Get the complete scheduling plan as a readable format.
        
        Returns:
            List of rounds with DPU assignments
        """
        plan = []
        for round_idx, round_tasksets in enumerate(self.scheduling_rounds):
            round_info = {
                "round": round_idx,
                "dpus": {}
            }
            
            for dpu_id, taskset in enumerate(round_tasksets):
                if taskset.tasks:
                    round_info["dpus"][dpu_id] = [task.task_id for task in taskset.tasks]
            
            plan.append(round_info)
        
        return plan
    
    def get_tasksets_by_rounds(self) -> List[List[TaskSet]]:
        """
        Get the scheduling plan as a simple list of lists of TaskSets.
        
        Returns:
            List[List[TaskSet]] where:
            - Outer list represents sequential rounds (round 0, round 1, etc.)
            - Inner list contains TaskSets that can run in parallel within that round
            - All TaskSets in round i must complete before TaskSets in round i+1 can start
            
        Example:
            [
                [TaskSet(dpu=0, tasks=[0]), TaskSet(dpu=1, tasks=[1])],  # Round 0: parallel
                [TaskSet(dpu=2, tasks=[2])],                              # Round 1: after round 0
                [TaskSet(dpu=0, tasks=[3]), TaskSet(dpu=3, tasks=[4])]   # Round 2: after round 1
            ]
        """
        rounds = []
        for round_tasksets in self.scheduling_rounds:
            # Only include TaskSets that have tasks
            round_with_tasks = [taskset for taskset in round_tasksets if len(taskset.tasks) > 0]
            if round_with_tasks:  # Only add round if it has tasks
                rounds.append(round_with_tasks)
        
        return rounds
    
    def reset_scheduling(self):
        """Reset the scheduling state to start fresh."""
        self.scheduled_tasks.clear()
        self.ready_to_schedule.clear()
        self.scheduling_rounds.clear()
        self.current_round = 0
        
        # Re-add tasks without dependencies as ready
        for task_id, task in self.tasks.items():
            if task_id not in self.dependencies:
                self.ready_to_schedule.add(task_id)
    