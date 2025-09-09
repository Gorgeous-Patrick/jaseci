from jaclang.runtimelib.archetype import WalkerAnchor
from jaclang.runtimelib.simulation.task import Task
from .dpu_mem_layout import DPUMemoryContext
from .upmem_codegen import (
    CodeGenContext,
    FunctionDef,
    TaskExecution,
    TypeDef,
    WalkerExecution,
)
from jaclang.runtimelib.constructs import NodeAnchor


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
    tasks: list[Task],
    all_nodes: list[NodeAnchor],
    walker: WalkerAnchor,
) -> CodeGenContext:
    node_types = get_node_types(all_nodes)
    walker_types = get_walker_types([walker])
    walker_abilities = get_walker_abilities(walker, walker_types[0], node_types)
    task_executions = [
        get_walker_executions(
            task=task,
            walker_type=walker_types[0],
            all_nodes=all_nodes,
            node_types=node_types,
            abilities_defs=walker_abilities,
        )
        for task in tasks
    ]
    max_node_size = max([task.start_mem_ctx.max_node_size() for task in tasks])
    max_walker_size = max([task.start_mem_ctx.max_walker_size() for task in tasks])
    return CodeGenContext(
        max_node_size=max_node_size,
        max_walker_size =max_walker_size,
        node_types=node_types,
        walker_types=walker_types,
        run_ability_functions=walker_abilities,
        task_executions=task_executions,
    )
