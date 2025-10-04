from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Creator(_jl.Walker):

    @_jl.entry
    @_jl.impl_patch_filename('object_spatial_references.jac')
    def create(self, here: _jl.Root) -> None:
        end = here
        i = 0
        while i < 3:
            _jl.connect(left=end, right=(end := node_a(val=i)))
            i += 1
        _jl.connect(left=end, right=(end := node_a(val=i + 10)), edge=connector, conn_assign=(('value',), (i,)))
        _jl.connect(left=(end := node_a(val=i + 10)), right=_jl.root(), edge=connector, conn_assign=(('value',), (i,)))
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class node_a(_jl.Node):
    val: int

    @_jl.entry
    @_jl.impl_patch_filename('object_spatial_references.jac')
    def make_something(self, visitor: Creator) -> None:
        i = 0
        while i < 5:
            print(f'wlecome to {self}')
            i += 1

class connector(_jl.Edge):
    value: int = 10
_jl.spawn(_jl.root(), Creator())
