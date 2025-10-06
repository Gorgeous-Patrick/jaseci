"""Implementations: Forward declarations and impl blocks for deferred definitions."""
from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
from enum import Enum, auto

@_jl.impl_patch_filename('/home/ninja/jaseci/jac/examples/reference/implementations.jac')
def compute(x: int, y: int) -> int:
    return x + y

class Vehicle(_jl.Obj):
    name: str = 'Car'
    speed: int = 0

    def accelerate(self) -> None:
        self.speed += 10

@_jl.sem('', {'LOW': '', 'MEDIUM': '', 'HIGH': ''})
class Priority(Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3

class Calculator(_jl.Obj):
    total: float = 0.0

    @_jl.impl_patch_filename('/home/ninja/jaseci/jac/examples/reference/implementations.jac')
    def add(self, value: float) -> None:
        self.total += value

    @_jl.impl_patch_filename('/home/ninja/jaseci/jac/examples/reference/implementations.jac')
    def subtract(self, value: float) -> None:
        self.total -= value

    @_jl.impl_patch_filename('/home/ninja/jaseci/jac/examples/reference/implementations.jac')
    def multiply(self, value: float) -> None:
        self.total *= value

    @_jl.impl_patch_filename('/home/ninja/jaseci/jac/examples/reference/implementations.jac')
    def get_result(self) -> float:
        return self.total
result = compute(5, 3)
v = Vehicle()
v.accelerate()
p = Priority.HIGH
calc = Calculator()
calc.add(10.5)
calc.multiply(2.0)
calc.subtract(5.0)
print(result, v.name, v.speed, p.value)
print('Calculator result:', calc.get_result())
