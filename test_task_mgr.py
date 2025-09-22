#!/usr/bin/env python3

import sys
sys.path.append('/Users/patrickli/Space/jaseci/jac')

from jaclang.runtimelib.simulation.task import Task, TaskMgr

# Test the TaskMgr with dependent tasks
def test_dependency_scheduling():
    mgr = TaskMgr()
    
    # Create tasks with dependencies: task1 -> task2 -> task3
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
    print("Scheduling Plan:")
    for round_info in plan:
        print(f"  Round {round_info['round']}: {round_info['dpus']}")
    
    print()
    print("Expected behavior:")
    print("  Round 0: {26: [0]} - Task 0 runs alone")
    print("  Round 1: {23: [1]} - Task 1 runs after task 0 completes")
    print("  Round 2: {25: [2]} - Task 2 runs after task 1 completes")

if __name__ == "__main__":
    test_dependency_scheduling()
