import jinja2
from pathlib import Path
from pydantic import BaseModel, Field


class TypeDef(BaseModel):
    name: str
    definition: str


class FunctionDef(BaseModel):
    name: str
    body: str = Field(
        description="Function body as a string, do not include the function signature."
    )
    walker_type: TypeDef
    node_type: TypeDef

    def full_name(self) -> str:
        return f"{self.name}_{self.walker_type.name}_{self.node_type.name}"


class WalkerExecution(BaseModel):
    node_ptr: int
    node_id: int
    func: FunctionDef


class CodeGenContext(BaseModel):
    node_types: list[TypeDef]
    walker_types: list[TypeDef]
    run_ability_functions: list[FunctionDef]
    walker_executions: list[WalkerExecution]


TEMPLATE_PATH = Path(__file__).parent / "dpu_template.jinja"


def gen_code(context: CodeGenContext) -> str:
    template_loader = jinja2.FileSystemLoader(searchpath=str(TEMPLATE_PATH.parent))
    template_env = jinja2.Environment(loader=template_loader)
    template = template_env.get_template(TEMPLATE_PATH.name)
    return template.render(
        node_types=context.node_types,
        walker_types=context.walker_types,
        run_ability_functions=context.run_ability_functions,
        walker_executions=context.walker_executions,
    )


if __name__ == "__main__":
    context = CodeGenContext(
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
        walker_executions=[
            WalkerExecution(
                node_ptr=1,
                node_id=1,
                func=FunctionDef(
                    name="run_ability_A",
                    body="/* function body */",
                    walker_type=TypeDef(
                        name="WalkerTypeA", definition="/* walker type definition */"
                    ),
                    node_type=TypeDef(
                        name="NodeTypeA", definition="/* node type definition */"
                    ),
                ),
            ),
            WalkerExecution(
                node_ptr=2,
                node_id=2,
                func=FunctionDef(
                    name="run_ability_B",
                    body="/* function body */",
                    walker_type=TypeDef(
                        name="WalkerTypeB", definition="/* walker type definition */"
                    ),
                    node_type=TypeDef(
                        name="NodeTypeB", definition="/* node type definition */"
                    ),
                ),
            ),
        ],
    )

    generated_code = gen_code(context)
    print(generated_code)
