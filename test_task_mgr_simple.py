#!/usr/bin/env python3

# Simple test of TaskMgr without importing the full Jac environment

from typing import Dict, List, Set, Optional, Any
from collections import defaultdict, deque

# Copy the classes directly to avoid import issues
DPU_NUM = 50
DPU_THREAD_NUM = 4

class Task:
    def __init__(self, task_id: int, dpu_id: int):
        self.task_id = task_id
        self.dpu_id = dpu_id

class TaskSet:
    def __init__(self, dpu_id: int):
        self.dpu_id = dpu_id
        self.tasks: list[Task] = []
    
    def add_task(self, task: Task):
        assert task.dpu_id == self.dpu_id
        assert len(self.tasks) < DPU_THREAD_NUM
        self.tasks.append(task)

class TaskMgr:
    """Task Manager for scheduling tasks across DPUs with dependencies."""
    
    def __init__(self):
        self.tasks: Dict[int, Task] = {}
        self.dependencies: Dict[int, int] = {}
        self.reverse_dependencies: Dict[int, Set[int]] = defaultdict(set)
        self.scheduled_tasks: Set[int] = set()
        self.ready_to_schedule: Set[int] = set()
        self.scheduling_rounds: List[List[TaskSet]] = []
        self.current_round: int = 0
        
    def add_task(self, task: Task, dependency_task_id: Optional[int] = None) -> int:
        task_id = task.task_id
        self.tasks[task_id] = task
        
        if dependency_task_id is not None:
            if dependency_task_id not in self.tasks:
                raise ValueError(f"Dependency task {dependency_task_id} not found")
            self.dependencies[task_id] = dependency_task_id
            self.reverse_dependencies[dependency_task_id].add(task_id)
        else:
            self.ready_to_schedule.add(task_id)
            
        return task_id
    
    def mark_task_scheduled(self, task_id: int):
        if task_id not in self.ready_to_schedule:
            raise ValueError(f"Task {task_id} is not ready to schedule")
            
        self.ready_to_schedule.remove(task_id)
        self.scheduled_tasks.add(task_id)
    
    def complete_round(self):
        newly_ready = []
        for task_id, task in self.tasks.items():
            if (task_id not in self.scheduled_tasks and 
                task_id not in self.ready_to_schedule and
                task_id in self.dependencies):
                
                dependency_id = self.dependencies[task_id]
                if dependency_id in self.scheduled_tasks:
                    newly_ready.append(task_id)
        
        for task_id in newly_ready:
            self.ready_to_schedule.add(task_id)
    
    def create_scheduling_round(self) -> List[TaskSet]:
        round_tasksets = [TaskSet(i) for i in range(DPU_NUM)]
        scheduled_in_round = []
        
        tasks_by_dpu: Dict[int, List[int]] = defaultdict(list)
        for task_id in self.ready_to_schedule:
            task = self.tasks[task_id]
            tasks_by_dpu[task.dpu_id].append(task_id)
        
        for dpu_id, task_ids in tasks_by_dpu.items():
            for task_id in task_ids[:DPU_THREAD_NUM]:
                task = self.tasks[task_id]
                round_tasksets[dpu_id].add_task(task)
                scheduled_in_round.append(task_id)
        
        for task_id in scheduled_in_round:
            self.mark_task_scheduled(task_id)
        
        self.complete_round()
        
        self.scheduling_rounds.append(round_tasksets)
        return round_tasksets
    
    def schedule_all_tasks(self) -> List[List[TaskSet]]:
        while self.has_tasks_to_schedule():
            round_tasksets = self.create_scheduling_round()
            if not any(len(ts.tasks) > 0 for ts in round_tasksets):
                remaining_tasks = list(self.ready_to_schedule)
                raise RuntimeError(f"Cannot schedule remaining tasks: {remaining_tasks}. "
                                 "Check for circular dependencies.")
        
        return self.scheduling_rounds
    
    def has_tasks_to_schedule(self) -> bool:
        return len(self.ready_to_schedule) > 0
    
    def get_scheduling_plan(self) -> List[Dict[str, Any]]:
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

# Test the TaskMgr with dependent tasks
def test_dependency_scheduling():
    mgr = TaskMgr()
    
    # Create tasks with dependencies: task0 -> task1 -> task2
    task0 = Task(task_id=0, dpu_id=26)  # Original task (no dependency)
    task1 = Task(task_id=1, dpu_id=23)  # Depends on task 0
    task2 = Task(task_id=2, dpu_id=25)  # Depends on task 1
    
    mgr.add_task(task0)                    # No dependency
    mgr.add_task(task1, dependency_task_id=0)  # Depends on task 0
    mgr.add_task(task2, dependency_task_id=1)  # Depends on task 1
    
    print("Tasks added:")
    print(f"  Task 0 (DPU 26): no dependency")
    print(f"  Task 1 (DPU 23): depends on task 0")
    print(f"  Task 2 (DPU 25): depends on task 1")
    print()
    
    # Schedule all tasks
    all_rounds = mgr.schedule_all_tasks()
    
    # Print the scheduling plan
    plan = mgr.get_scheduling_plan()
    print("Actual Scheduling Plan:")
    for round_info in plan:
        print(f"  Round {round_info['round']}: {round_info['dpus']}")
    
    print()
    print("Expected behavior:")
    print("  Round 0: {26: [0]} - Task 0 runs alone")
    print("  Round 1: {23: [1]} - Task 1 runs after task 0 completes")
    print("  Round 2: {25: [2]} - Task 2 runs after task 1 completes")

if __name__ == "__main__":
    test_dependency_scheduling()
