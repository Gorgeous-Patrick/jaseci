from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def foo(x: int, y: int, z: int) -> None:
    return (x * y, y * z)
a = 5
output = foo(x=4, y=4 if a % 3 == 2 else 3, z=9)
print(output)
result = foo(1, 2, 3)
print(result)
mixed = foo(1, y=2, z=3)
print(mixed)
