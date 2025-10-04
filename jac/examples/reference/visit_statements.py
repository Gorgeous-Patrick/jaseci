from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Visitor(_jl.Walker):

    @_jl.entry
    def travel(self, here: _jl.Root) -> None:
        if not _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit())):
            _jl.visit(self, _jl.root())
            _jl.disengage(self)
            return

class TypedVisitor(_jl.Walker):

    @_jl.entry
    def explore(self, here: _jl.Root) -> None:
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class ConditionalVisitor(_jl.Walker):
    count: int = 0

    @_jl.entry
    def check(self, here: _jl.Root) -> None:
        _jl.visit(self, _jl.root())
        if self.count < 5:
            _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))
            self.count += 1

class item(_jl.Node):

    @_jl.entry
    def speak(self, visitor: Visitor) -> None:
        print('Hey There!!!')

class Person(_jl.Node):
    name: str

    @_jl.entry
    def greet(self, visitor: TypedVisitor) -> None:
        print(f'Hello from {self.name}')
i = 0
while i < 5:
    _jl.connect(left=_jl.root(), right=item())
    i += 1
_jl.spawn(_jl.root(), Visitor())
