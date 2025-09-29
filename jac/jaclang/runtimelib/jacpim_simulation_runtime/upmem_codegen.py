"""Simulator code generator."""

from dataclasses import dataclass
from pathlib import Path

import jinja2


@dataclass
class MemoryRange:
    """A range of memory."""

    ptr: int
    size: int

    def add_offset(self, offset: int) -> "MemoryRange":
        """Add offset to self.ptr."""
        return MemoryRange(ptr=self.ptr + offset, size=self.size)


@dataclass
class TypeDef:
    """The definition of a struct type in the code."""

    name: str
    definition: str


@dataclass
class FunctionDef:
    """The definition of a function."""

    name: str
    body: str
    walker_type: TypeDef
    node_type: TypeDef

    def full_name(self) -> str:
        """Get the fullname for a function."""
        return f"{self.name}_{self.walker_type.name}_{self.node_type.name}"


@dataclass
class WalkerExecution:
    """Metadata for code that walker runs on one single node."""

    node_range: MemoryRange
    node_id: int
    func: FunctionDef


@dataclass
class TaskExecution:
    """Metadata for code that walker runs on a list of nodes."""

    task_id: int
    walker_range: MemoryRange
    walker_executions: list[WalkerExecution]


@dataclass
class CodeGenContext:
    """Metadata for code generation."""

    max_node_size: int
    max_walker_size: int
    node_types: list[TypeDef]
    walker_types: list[TypeDef]
    run_ability_functions: list[FunctionDef]
    taskset_execution: list[TaskExecution]


TEMPLATE_PATH = Path(__file__).parent / "dpu_template.jinja"


def gen_code(context: CodeGenContext) -> str:
    """Generate code."""
    template_loader = jinja2.FileSystemLoader(searchpath=str(TEMPLATE_PATH.parent))
    template_env = jinja2.Environment(loader=template_loader)
    template = template_env.get_template(TEMPLATE_PATH.name)
    return template.render(
        # node_types=context.node_types,
        # walker_types=context.walker_types,
        # run_ability_functions=context.run_ability_functions,
        # task_executions=context.task_executions,
        context
    )


if __name__ == "__main__":
    context = CodeGenContext(
        max_node_size=16,
        max_walker_size=64,
        node_types=[
            TypeDef(name="NodeTypeA", definition="int id; float value;"),
            TypeDef(name="NodeTypeB", definition="int id; double value;"),
        ],
        walker_types=[TypeDef(name="WalkerTypeA", definition="int id;")],
        run_ability_functions=[
            FunctionDef(
                name="run_ability_A",
                body="/* function body */",
                walker_type=TypeDef(
                    name="WalkerTypeA", definition="/* walker type definition */"
                ),
                node_type=TypeDef(
                    name="NodeTypeA", definition="/* node type definition */"
                ),
            ),
            FunctionDef(
                name="run_ability_B",
                body="/* function body */",
                walker_type=TypeDef(
                    name="WalkerTypeB", definition="/* walker type definition */"
                ),
                node_type=TypeDef(
                    name="NodeTypeB", definition="/* node type definition */"
                ),
            ),
        ],
        taskset_execution=[
            TaskExecution(
                task_id=0,
                walker_range=MemoryRange(ptr=30, size=80),
                walker_executions=[
                    WalkerExecution(
                        node_range=MemoryRange(ptr=30, size=80),
                        node_id=1,
                        func=FunctionDef(
                            name="run_ability_A",
                            body="/* function body */",
                            walker_type=TypeDef(
                                name="WalkerTypeA",
                                definition="/* walker type definition */",
                            ),
                            node_type=TypeDef(
                                name="NodeTypeA",
                                definition="/* node type definition */",
                            ),
                        ),
                    ),
                    WalkerExecution(
                        node_range=MemoryRange(ptr=30, size=80),
                        node_id=2,
                        func=FunctionDef(
                            name="run_ability_B",
                            body="/* function body */",
                            walker_type=TypeDef(
                                name="WalkerTypeB",
                                definition="/* walker type definition */",
                            ),
                            node_type=TypeDef(
                                name="NodeTypeB",
                                definition="/* node type definition */",
                            ),
                        ),
                    ),
                ],
            )
        ]
        * 3,
    )

    generated_code = gen_code(context)
    print(generated_code)
