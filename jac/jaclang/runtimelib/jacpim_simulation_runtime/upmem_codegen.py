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
class CodeGenContext:
    """Metadata for code generation."""

    max_node_size: int
    max_walker_size: int
    node_types: list[TypeDef]
    walker_types: list[TypeDef]
    run_ability_functions: list[FunctionDef]
    metadata_definition: str
    container_object_definition: str


TEMPLATE_PATH = Path(__file__).parent / "dpu_template.jinja"


def gen_code(context: CodeGenContext) -> str:
    """Generate code."""
    template_loader = jinja2.FileSystemLoader(searchpath=str(TEMPLATE_PATH.parent))
    template_env = jinja2.Environment(loader=template_loader)
    template = template_env.get_template(TEMPLATE_PATH.name)
    return template.render(vars(context))


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
        metadata_definition="/* metadata struct definition */",
        container_object_definition="/* container object definition */",
    )

    generated_code = gen_code(context)
    print(generated_code)
