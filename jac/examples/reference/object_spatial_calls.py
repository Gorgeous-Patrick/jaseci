from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Creator(_jl.Walker):

    @_jl.entry
    @_jl.impl_patch_filename('object_spatial_calls.jac')
    def func2(self, here: _jl.Root) -> None:
        end = here
        i = 0
        while i < 5:
            _jl.connect(left=end, right=(end := node_1(val=i + 1)))
            i += 1
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class node_1(_jl.Node):
    val: int

    @_jl.entry
    @_jl.impl_patch_filename('object_spatial_calls.jac')
    def func_1(self, visitor: Creator) -> None:
        print('visiting ', self)
        _jl.visit(visitor, _jl.refs(_jl.Path(self)._out().visit()))
_jl.spawn(_jl.root(), Creator())
_jl.spawn(_jl.root(), Creator())
