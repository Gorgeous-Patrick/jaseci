from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
print('Welcome to the world of Jaseci!')

def add(x: int, y: int) -> int:
    return x + y
print(add(10, 89))
x = 42
if x > 0:
    print('Positive')
