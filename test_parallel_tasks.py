#!/usr/bin/env python3

# Test TaskMgr with parallel tasks that depend on the same parent

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

# Test scenarios
def test_parallel_dependencies():
    print("=" * 60)
    print("TEST 1: Parallel Dependencies (Fan-out)")
    print("=" * 60)
    
    mgr = TaskMgr()
    
    # Create tasks where multiple tasks depend on task 0
    # Task 0 (parent) -> Task 1, Task 2, Task 3 (all in parallel)
    task0 = Task(task_id=0, dpu_id=10)  # Parent task
    task1 = Task(task_id=1, dpu_id=20)  # Child 1
    task2 = Task(task_id=2, dpu_id=30)  # Child 2  
    task3 = Task(task_id=3, dpu_id=40)  # Child 3
    
    mgr.add_task(task0)                    # No dependency
    mgr.add_task(task1, dependency_task_id=0)  # Depends on task 0
    mgr.add_task(task2, dependency_task_id=0)  # Depends on task 0
    mgr.add_task(task3, dependency_task_id=0)  # Depends on task 0
    
    print("Tasks added:")
    print(f"  Task 0 (DPU 10): no dependency")
    print(f"  Task 1 (DPU 20): depends on task 0")
    print(f"  Task 2 (DPU 30): depends on task 0")
    print(f"  Task 3 (DPU 40): depends on task 0")
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
    print("  Round 0: {10: [0]} - Task 0 runs alone")
    print("  Round 1: {20: [1], 30: [2], 40: [3]} - Tasks 1,2,3 run in parallel after task 0")
    print()

def test_complex_dependencies():
    print("=" * 60)
    print("TEST 2: Complex Dependencies (Fan-out + Fan-in)")
    print("=" * 60)
    
    mgr = TaskMgr()
    
    # Create a more complex dependency graph:
    # Task 0 -> Task 1, Task 2, Task 3 (parallel)
    # Task 1, Task 2, Task 3 -> Task 4 (convergence)
    task0 = Task(task_id=0, dpu_id=10)  # Root
    task1 = Task(task_id=1, dpu_id=20)  # Child 1
    task2 = Task(task_id=2, dpu_id=30)  # Child 2
    task3 = Task(task_id=3, dpu_id=40)  # Child 3
    task4 = Task(task_id=4, dpu_id=15)  # Depends on task 1
    task5 = Task(task_id=5, dpu_id=25)  # Depends on task 2
    task6 = Task(task_id=6, dpu_id=35)  # Depends on task 3
    
    mgr.add_task(task0)                    # Root task
    mgr.add_task(task1, dependency_task_id=0)  # Level 1
    mgr.add_task(task2, dependency_task_id=0)  # Level 1
    mgr.add_task(task3, dependency_task_id=0)  # Level 1
    mgr.add_task(task4, dependency_task_id=1)  # Level 2
    mgr.add_task(task5, dependency_task_id=2)  # Level 2
    mgr.add_task(task6, dependency_task_id=3)  # Level 2
    
    print("Tasks added:")
    print(f"  Task 0 (DPU 10): no dependency")
    print(f"  Task 1 (DPU 20): depends on task 0")
    print(f"  Task 2 (DPU 30): depends on task 0") 
    print(f"  Task 3 (DPU 40): depends on task 0")
    print(f"  Task 4 (DPU 15): depends on task 1")
    print(f"  Task 5 (DPU 25): depends on task 2")
    print(f"  Task 6 (DPU 35): depends on task 3")
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
    print("  Round 0: {10: [0]} - Task 0 runs alone")
    print("  Round 1: {20: [1], 30: [2], 40: [3]} - Tasks 1,2,3 run in parallel")
    print("  Round 2: {15: [4], 25: [5], 35: [6]} - Tasks 4,5,6 run in parallel")
    print()

def test_dpu_capacity_limits():
    print("=" * 60)
    print("TEST 3: DPU Capacity Limits")
    print("=" * 60)
    
    mgr = TaskMgr()
    
    # Create more parallel tasks than DPU capacity on same DPU
    task0 = Task(task_id=0, dpu_id=10)  # Parent
    task1 = Task(task_id=1, dpu_id=20)  # Same DPU as task2-5
    task2 = Task(task_id=2, dpu_id=20)  # Same DPU 
    task3 = Task(task_id=3, dpu_id=20)  # Same DPU
    task4 = Task(task_id=4, dpu_id=20)  # Same DPU
    task5 = Task(task_id=5, dpu_id=20)  # Same DPU (exceeds DPU_THREAD_NUM=4)
    
    mgr.add_task(task0)                    # Root
    mgr.add_task(task1, dependency_task_id=0)  
    mgr.add_task(task2, dependency_task_id=0)  
    mgr.add_task(task3, dependency_task_id=0)  
    mgr.add_task(task4, dependency_task_id=0)  
    mgr.add_task(task5, dependency_task_id=0)  
    
    print("Tasks added:")
    print(f"  Task 0 (DPU 10): no dependency")
    print(f"  Task 1-5 (DPU 20): all depend on task 0")
    print(f"  DPU capacity limit: {DPU_THREAD_NUM}")
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
    print("  Round 0: {10: [0]} - Task 0 runs alone")
    print("  Round 1: {20: [1, 2, 3, 4]} - First 4 tasks on DPU 20")
    print("  Round 2: {20: [5]} - Remaining task on DPU 20")
    print()

if __name__ == "__main__":
    test_parallel_dependencies()
    test_complex_dependencies() 
    test_dpu_capacity_limits()
