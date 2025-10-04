from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class node_a(_jl.Node):
    value: int

class Creator(_jl.Walker):

    @_jl.entry
    @_jl.impl_patch_filename('connect_expressions.jac')
    def create(self, here: _jl.Root) -> None:
        end = here
        i = 0
        while i < 7:
            if i % 2 == 0:
                _jl.connect(left=end, right=(end := node_a(value=i)))
            else:
                _jl.connect(left=end, right=(end := node_a(value=i + 10)), edge=MyEdge, conn_assign=(('val',), (i,)))
            i += 1

    @_jl.entry
    @_jl.impl_patch_filename('connect_expressions.jac')
    def travel(self, here: _jl.Root | node_a) -> None:
        for i in _jl.refs(_jl.Path(here)._out(edge=lambda i: isinstance(i, MyEdge) and i.val <= 6)):
            print(i.value)
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class MyEdge(_jl.Edge):
    val: int = 5
if __name__ == '__main__':
    _jl.spawn(_jl.root(), Creator())
