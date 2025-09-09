from jaclang.runtimelib.archetype import WalkerAnchor
from .dpu_mem_layout import DPUMemoryContext
from .upmem_codegen import CodeGenContext, FunctionDef, TypeDef, WalkerExecution
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
    mem_context: DPUMemoryContext,
    trace: list[int],
    all_nodes: list[NodeAnchor],
    walker_type: TypeDef,
    node_types: list[TypeDef],
    abilities_defs: list[FunctionDef],
) -> list[WalkerExecution]:
    res: list[WalkerExecution] = []
    for node_id in trace:
        node_ptr = mem_context.get_node_ptr(node_id)
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
        exe = WalkerExecution(node_ptr=node_ptr, node_id=node_id, func=func_def)
        res.append(exe)
    return res


def context_gen(
    mem_context: DPUMemoryContext,
    partial_trace: list[int],
    all_nodes: list[NodeAnchor],
    walker: WalkerAnchor,
) -> CodeGenContext:
    node_types = get_node_types(all_nodes)
    walker_types = get_walker_types([walker])
    walker_abilities = get_walker_abilities(walker, walker_types[0], node_types)
    executions = get_walker_executions(
        mem_context=mem_context,
        trace=partial_trace,
        all_nodes=all_nodes,
        walker_type=walker_types[0],
        node_types=node_types,
        abilities_defs=walker_abilities,
    )
    return CodeGenContext(
        node_types=node_types,
        walker_types=walker_types,
        run_ability_functions=walker_abilities,
        walker_executions=executions,
    )
