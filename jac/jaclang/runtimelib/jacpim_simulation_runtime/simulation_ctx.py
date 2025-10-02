"""Simulation context generation for UPMEM codegen."""

from jaclang.runtimelib.constructs import NodeArchetype, WalkerArchetype
from jaclang.runtimelib.jacpim_perf_measure.cpu_run_ctx import JacPIMCPURunCtx
from jaclang.runtimelib.jacpim_static_analysis.info_extract import extract_name
from jaclang.runtimelib.jacpim_static_analysis.static_ctx import JacPIMStaticCtx

from .upmem_codegen import (
    CodeGenContext,
    FunctionDef,
    TypeDef,
    gen_code,
)


def get_node_types(all_nodes: list[NodeArchetype]) -> list[TypeDef]:
    """Extract node types from all nodes."""
    extracted_nodes: dict[str, str] = {}
    for node in all_nodes:
        type_name = extract_name(node)
        extracted_nodes[type_name] = node.get_type_def()
    res = [
        TypeDef(name=name, definition=definition)
        for name, definition in extracted_nodes.items()
    ]
    return res


def get_walker_types(all_walkers: list[WalkerArchetype]) -> list[TypeDef]:
    """Extract walker types from all walkers."""
    extracted_walkers: dict[str, str] = {}
    for walker in all_walkers:
        type_name = extract_name(walker)
        extracted_walkers[type_name] = walker.get_type_def()
    res = [
        TypeDef(name=name, definition=definition)
        for name, definition in extracted_walkers.items()
    ]
    return res


def get_walker_abilities(
    walkers: list[WalkerArchetype], walker_type: TypeDef, node_types: list[TypeDef]
) -> list[FunctionDef]:
    """Extract walker abilities from all walkers."""
    result: list[FunctionDef] = []
    for walker in walkers:
        object_methods = [
            method_name
            for method_name in dir(walker)
            if callable(getattr(walker, method_name))
            and method_name.startswith("get_impl_")
        ]
        for object_method in object_methods:
            name = object_method.split("_")[2]
            node_type_name = object_method.split("_")[4]
            node_type_def = [
                node_type
                for node_type in node_types
                if node_type.name == node_type_name
            ][0]
            func_def = FunctionDef(
                name=name,
                body=getattr(walker, object_method)(),
                walker_type=walker_type,
                node_type=node_type_def,
            )
            result.append(func_def)
    return result


def context_gen() -> CodeGenContext:
    """Generate the codegen context."""
    all_nodes = JacPIMStaticCtx.get_all_nodes()
    all_walkers = JacPIMCPURunCtx.get_all_walkers()
    node_types = get_node_types(all_nodes)
    walker_types = get_walker_types(all_walkers)
    walker_abilities = get_walker_abilities(all_walkers, walker_types[0], node_types)

    max_node_size = max([len(node.get_byte_stream()) for node in all_nodes])
    max_walker_size = max([len(walker.get_byte_stream()) for walker in all_walkers])

    return CodeGenContext(
        max_node_size=max_node_size,
        max_walker_size=max_walker_size,
        node_types=node_types,
        walker_types=walker_types,
        run_ability_functions=walker_abilities,
    )


def save_codegen_file(file_path: str) -> None:
    """Save the codegen file to the specified path."""
    context = context_gen()
    code = gen_code(context)
    with open(file_path, "w") as f:
        f.write(code)
