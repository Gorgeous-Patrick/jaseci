from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Adder(_jl.Walker):

    @_jl.entry
    @_jl.impl_patch_filename('object_spatial_spawn_expressions.jac')
    def do(self, here: _jl.Root) -> None:
        _jl.connect(left=here, right=node_a())
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class node_a(_jl.Node):
    x: int = 0
    y: int = 0

    @_jl.entry
    @_jl.impl_patch_filename('object_spatial_spawn_expressions.jac')
    def add(self, visitor: Adder) -> None:
        self.x = 550
        self.y = 450
        print(int(self.x) + int(self.y))
_jl.spawn(Adder(), _jl.root())
