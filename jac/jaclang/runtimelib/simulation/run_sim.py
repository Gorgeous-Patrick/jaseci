import json
from queue import Queue
import shutil
from jaclang.runtimelib.archetype import WalkerAnchor
from jaclang.runtimelib.simulation.sim_output_parser import SimStats, parse_sim_stats, ThreadScheduler
from jaclang.runtimelib.simulation.task import Task
import traceback
import sys
import os

from .upmem_codegen import (
    CodeGenContext,
    FunctionDef,
    TaskExecution,
    TypeDef,
    WalkerExecution,
    gen_code,
)
from .task import TaskSet, Task, TaskMgr
from jaclang.runtimelib.constructs import NodeAnchor
from queue import Queue
from pathlib import Path


def get_node_types(all_nodes: list[NodeAnchor]) -> list[TypeDef]:
    extracted_nodes: dict[str, str] = {}
    for node in all_nodes:
        type_name = str(node.archetype).split(chr(40))[0]
        extracted_nodes[type_name] = node.archetype.get_type_def()
    res = [
        TypeDef(name=name, definition=definition)
        for name, definition in extracted_nodes.items()
    ]
    return res


def get_walker_types(all_walkers: list[WalkerAnchor]) -> list[TypeDef]:
    extracted_walkers: dict[str, str] = {}
    for walker in all_walkers:
        type_name = str(walker.archetype).split(chr(40))[0]
        extracted_walkers[type_name] = walker.archetype.get_type_def()
    res = [
        TypeDef(name=name, definition=definition)
        for name, definition in extracted_walkers.items()
    ]
    return res


def get_walker_abilities(
    walker: WalkerAnchor, walker_type: TypeDef, node_types: list[TypeDef]
) -> list[FunctionDef]:
    result: list[FunctionDef] = []
    object_methods = [
        method_name
        for method_name in dir(walker.archetype)
        if callable(getattr(walker.archetype, method_name))
        and method_name.startswith("get_impl_")
    ]
    for object_method in object_methods:
        name = object_method.split("_")[2]
        node_type_name = object_method.split("_")[4]
        node_type_def = [
            node_type for node_type in node_types if node_type.name == node_type_name
        ][0]
        func_def = FunctionDef(
            name=name,
            body=getattr(walker.archetype, object_method)(),
            walker_type=walker_type,
            node_type=node_type_def,
        )
        result.append(func_def)
    return result


def get_walker_executions(
    task: Task,
    walker_type: TypeDef,
    all_nodes: list[NodeAnchor],
    node_types: list[TypeDef],
    abilities_defs: list[FunctionDef],
) -> TaskExecution:
    res: list[WalkerExecution] = []
    walker_range = task.start_mem_ctx.get_walker_range(0)
    for node_id in task.trace:
        node_range = task.start_mem_ctx.get_node_range(node_id)
        node = all_nodes[node_id]
        node_type_name = str(node.archetype).split(chr(40))[0]
        node_type_def = [
            node_type for node_type in node_types if node_type.name == node_type_name
        ][0]
        func_def = [
            func
            for func in abilities_defs
            if func.walker_type is walker_type and func.node_type is node_type_def
        ][0]
        exe = WalkerExecution(node_range=node_range, node_id=node_id, func=func_def)
        res.append(exe)
    return TaskExecution(task_id=task.task_id, walker_executions=res, walker_range=walker_range)


def context_gen(
    taskset: TaskSet,
    all_nodes: list[NodeAnchor],
    walker: WalkerAnchor,
) -> CodeGenContext:
    node_types = get_node_types(all_nodes)
    walker_types = get_walker_types([walker])
    walker_abilities = get_walker_abilities(walker, walker_types[0], node_types)
    taskset_execution = [get_walker_executions(
        task=task,
        walker_type=walker_types[0],
        all_nodes=all_nodes,
        node_types=node_types,
        abilities_defs=walker_abilities,
    ) for task in taskset.tasks]

    # Get the max node size and walker size from the taskset start_mem_ctx
    max_node_size = max(
        [task.start_mem_ctx.max_node_size() for task in taskset.tasks]
    )
    max_walker_size = max(
        [task.start_mem_ctx.max_walker_size() for task in taskset.tasks]
    )

    return CodeGenContext(
        max_node_size=max_node_size,
        max_walker_size =max_walker_size,
        node_types=node_types,
        walker_types=walker_types,
        run_ability_functions=walker_abilities,
        taskset_execution=taskset_execution,
    )


class uPIMulator:
    def get_simulator_path(self, sim_id: int) -> Path:
        return Path.home() / f"uPIMulators/uPIMulator{sim_id}"
        # return f"~/uPIMulators/uPIMulator{sim_id}"

    def __init__(self, sim_num: int):
        self.sim_num = sim_num
        for sim in range(sim_num):
            # Copy ~/uPIMulator to ~/uPIMulators/uPIMulator{sim}
            import os
            # if not os.path.exists("~/uPIMulators"):
            if not (Path.home() / "uPIMulators").exists():
                # os.mkdir("~/uPIMulators")
                os.mkdir(Path.home() / "uPIMulators")
            if self.get_simulator_path(sim).exists():
                shutil.rmtree(self.get_simulator_path(sim))
            shutil.copytree(Path.home() / "uPIMulator", self.get_simulator_path(sim))
            if (Path.home() / "uPIMulators/results").exists():
                shutil.rmtree(Path.home() / "uPIMulators/results")
            os.mkdir(Path.home() / "uPIMulators/results")

    def run_single_sim(self, sim_id: int, taskset: TaskSet, context: CodeGenContext):
        import os
        import subprocess
        sim_path = self.get_simulator_path(sim_id)
        # Write the src code to {simulator_path}/golang/uPIMulator/benchmark/GEN/dpu/task.c
        with open(sim_path / "golang/uPIMulator/benchmark/GEN/dpu/task.c", "w") as f:
            f.write(gen_code(context))
        assert taskset.mem_ctx is not None
        taskset.mem_ctx.dump_to_file(
            f"{sim_path}/golang/uPIMulator/Task.bin"
        )
        # Run the simulator with pwd: {simulator_path}/golang/uPIMulator
        # chmod +x run.sh
        os.chmod(sim_path / "golang/uPIMulator/run.sh", 0o755)
        # command: run.sh
        os.environ["NUM_TASKLETS"] = str(len(taskset.tasks))
        result = subprocess.run(["./run.sh"], cwd=sim_path / "golang/uPIMulator", capture_output=True, env=os.environ)

        # Copy the result folder from {simulator_path}/golang/uPIMulator/bin/
        # to ~/uPIMulators/results
        if (Path.home() / f"uPIMulators/results/taskset_{taskset.task_set_id}").exists():
            shutil.rmtree(Path.home() / f"uPIMulators/results/taskset_{taskset.task_set_id}")
        shutil.copytree(
            self.get_simulator_path(sim_id) / "golang/uPIMulator/bin/",
            Path.home() / f"uPIMulators/results/taskset_{taskset.task_set_id}",
        )
        # Write the stdout and stderr to ~/uPIMulators/results/task_{task.task_id}/output.txt
        with open(Path.home() / f"uPIMulators/results/taskset_{taskset.task_set_id}/output.txt", "w") as f:
            f.write("STDOUT:\n")
            f.write(result.stdout.decode())
            f.write("\n\nSTDERR:\n")
            f.write(result.stderr.decode())
    
    def run_single_round_sim(self, tasksets: list[TaskSet], all_nodes: list[NodeAnchor], walker: WalkerAnchor):
        # I want to run self.run_single_sim in parallel for sim_num sims
        # Task with the same sim_id will be run in the same simulator, and running multiple tasks in the same simulator is not parallel
        tasksets_and_contexts = [
            (taskset, context_gen(taskset=taskset, all_nodes=all_nodes, walker=walker)) for taskset in tasksets
        ]
        q = Queue()

        def worker(sim_id: int):
            while True:
                taskset, context = q.get()
                if taskset is None:
                    q.task_done()
                    break
                try:
                    self.run_single_sim(sim_id, taskset, context)
                except Exception:  # crash whole program on any task failure
                    # Print the traceback for debugging, then exit *immediately*.
                    traceback.print_exc(file=sys.stderr)
                    sys.stderr.flush()
                    os._exit(1)  # hard exit: no cleanup, no finally, no atexit
                finally:
                    q.task_done()
        import threading
        threads = []
        for sim_id in range(self.sim_num):
            t = threading.Thread(target=worker, args=(sim_id,))
            t.start()
            threads.append(t)
        for taskset, context in tasksets_and_contexts:
            q.put((taskset, context))
        # block until all tasks are done
        q.join()
        # stop workers
        for _ in range(self.sim_num):
            q.put((None, None))
        for t in threads:
            t.join()
        

    def run_sims(self, task_mgr: TaskMgr, all_nodes: list[NodeAnchor], walker: WalkerAnchor):
        rounds = task_mgr.get_tasksets_by_rounds()
        rounds_save_path = Path.home() / "uPIMulators/results/rounds.json"
        rounds_serializable = [[taskset.task_set_id for taskset in round] for round in rounds]
        with open(rounds_save_path, "w") as f:
            json.dump(rounds_serializable, f, indent=4)
        print(f"Scheduling plan has {len(rounds)} rounds")
        for round in rounds:
            print(f"Running round with {len(round)} tasksets")
            self.run_single_round_sim(round, all_nodes, walker)

    def get_results(self) -> dict[int, SimStats]:
        results: dict[int, SimStats] = {}
        for result_dir in (Path.home() / "uPIMulators/results").iterdir():
            if result_dir.is_dir() and result_dir.name.startswith("taskset_"):
                task_id = int(result_dir.name.split("_")[1])
                with open(result_dir / "log.txt", "r") as f:
                    output = f.read()
                stats = parse_sim_stats(output)
                results[task_id] = stats
        return results
    
def save_result_sum(stats: dict[int, SimStats]):
    print( f"Got {len(stats)} simulation results")
    # 1. Read the rounds file
    rounds_path = Path.home() / "uPIMulators/results/rounds.json"
    with open(rounds_path, "r") as f:
        rounds = json.load(f)
    print(f"Scheduling plan has {len(rounds)} rounds")
    # 2. For each round, get the longest total time of all tasksets in the round
    total_run_time = 0
    for round in rounds:
        print(f"Round with {len(round)} tasksets")
        max_time = max(stats[taskset_id].thread_scheduler.breakdown_dma + stats[taskset_id].thread_scheduler.breakdown_etc + stats[taskset_id].thread_scheduler.breakdown_run for taskset_id in round)
        print(f"Round time: {max_time} cycles")
        total_run_time += max_time
    print(f"Total run time: {total_run_time} cycles")
    print(f"Total Cross DPU Jumps: {Task.TASK_COUNT - 1}")

    # total = ThreadScheduler()
    # for stat in stats:
    #     total.breakdown_dma += stat.thread_scheduler.breakdown_dma
    #     total.breakdown_etc += stat.thread_scheduler.breakdown_etc
    #     total.breakdown_run += stat.thread_scheduler.breakdown_run
    # with open(Path.home() / "uPIMulators/results/summary.txt", "w") as f:
    #     json.dump(total.__dict__, f, indent=4)
    MAPPING = os.environ.get("MAPPING", "UNKNOWN")
    test_name = os.getenv("TEST_NAME", "default_test") + "_" + MAPPING
    copy_result_path = Path.home() / f"uPIMulators/results_{test_name}"
    if copy_result_path.exists():
        shutil.rmtree(copy_result_path)
    shutil.copytree(Path.home() / "uPIMulators/results", copy_result_path)
