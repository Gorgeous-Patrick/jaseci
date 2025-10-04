from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Visitor(_jl.Walker):

    @_jl.entry
    def travel(self, here: _jl.Root) -> None:
        if not _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit())):
            _jl.visit(self, _jl.root())

class item(_jl.Node):

    @_jl.entry
    def speak(self, visitor: Visitor) -> None:
        print('Hey There!!!')
        _jl.disengage(visitor)
        return
i = 0
while i < 5:
    _jl.connect(left=_jl.root(), right=item())
    i += 1
_jl.spawn(_jl.root(), Visitor())
