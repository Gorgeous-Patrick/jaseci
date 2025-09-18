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
    task: Task,
    all_nodes: list[NodeAnchor],
    walker: WalkerAnchor,
) -> CodeGenContext:
    node_types = get_node_types(all_nodes)
    walker_types = get_walker_types([walker])
    walker_abilities = get_walker_abilities(walker, walker_types[0], node_types)
    task_executions = get_walker_executions(
        task=task,
        walker_type=walker_types[0],
        all_nodes=all_nodes,
        node_types=node_types,
        abilities_defs=walker_abilities,
    )
    max_node_size = task.start_mem_ctx.max_node_size()
    max_walker_size = task.start_mem_ctx.max_walker_size()
    return CodeGenContext(
        max_node_size=max_node_size,
        max_walker_size =max_walker_size,
        node_types=node_types,
        walker_types=walker_types,
        run_ability_functions=walker_abilities,
        task_execution=task_executions,
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

    def run_single_sim(self, sim_id: int, task: Task, context: CodeGenContext):
        import os
        import subprocess
        sim_path = self.get_simulator_path(sim_id)
        # Write the src code to {simulator_path}/golang/uPIMulator/benchmark/GEN/dpu/task.c
        with open(sim_path / "golang/uPIMulator/benchmark/GEN/dpu/task.c", "w") as f:
            f.write(gen_code(context))
        task.start_mem_ctx.dump_to_file(
            f"{sim_path}/golang/uPIMulator/Task.bin"
        )
        # Run the simulator with pwd: {simulator_path}/golang/uPIMulator
        # chmod +x run.sh
        os.chmod(sim_path / "golang/uPIMulator/run.sh", 0o755)
        # command: run.sh
        result = subprocess.run(["./run.sh"], cwd=sim_path / "golang/uPIMulator", capture_output=True)

        # Copy the result folder from {simulator_path}/golang/uPIMulator/bin/
        # to ~/uPIMulators/results
        if (Path.home() / f"uPIMulators/results/task_{task.task_id}").exists():
            shutil.rmtree(Path.home() / f"uPIMulators/results/task_{task.task_id}")
        shutil.copytree(
            self.get_simulator_path(sim_id) / "golang/uPIMulator/bin/",
            Path.home() / f"uPIMulators/results/task_{task.task_id}",
        )
        # Write the stdout and stderr to ~/uPIMulators/results/task_{task.task_id}/output.txt
        with open(Path.home() / f"uPIMulators/results/task_{task.task_id}/output.txt", "w") as f:
            f.write("STDOUT:\n")
            f.write(result.stdout.decode())
            f.write("\n\nSTDERR:\n")
            f.write(result.stderr.decode())

    def run_sims(self, tasks: list[Task], all_nodes: list[NodeAnchor], walker: WalkerAnchor):
        print(f"Running {len(tasks)} tasks on {self.sim_num} simulators")
        tasks_and_contexts = [
            (task,context_gen(task=task, all_nodes=all_nodes, walker=walker)) for task in tasks
        ]
        # I want to run self.run_single_sim in parallel for sim_num sims
        # Task with the same sim_id will be run in the same simulator, and running multiple tasks in the same simulator is not parallel
        q = Queue()

        def worker(sim_id: int):
            while True:
                task, context = q.get()
                if task is None:
                    q.task_done()
                    break
                try:
                    self.run_single_sim(sim_id, task, context)
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
        for task, context in tasks_and_contexts:
            q.put((task, context))
        # block until all tasks are done
        q.join()
        # stop workers
        for _ in range(self.sim_num):
            q.put((None, None))
        for t in threads:
            t.join()
    def get_results(self) -> list[SimStats]:
        results: list[SimStats] = []
        for result_dir in (Path.home() / "uPIMulators/results").iterdir():
            if result_dir.is_dir() and result_dir.name.startswith("task_"):
                with open(result_dir / "log.txt", "r") as f:
                    output = f.read()
                stats = parse_sim_stats(output)
                results.append(stats)
        return results
    
def get_result_sum(stats: list[SimStats]) -> ThreadScheduler:
    print( f"Got {len(stats)} simulation results")
    total = ThreadScheduler()
    for stat in stats:
        total.breakdown_dma += stat.thread_scheduler.breakdown_dma
        total.breakdown_etc += stat.thread_scheduler.breakdown_etc
        total.breakdown_run += stat.thread_scheduler.breakdown_run
    return total
