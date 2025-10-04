from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def double(x: int) -> int:
    return x * 2

def triple(x: int) -> int:
    return x * 3

def negate(x: int) -> int:
    return -x
number = 5
result = double(number)
print(result)
x = (lambda n: n * 3)(10)
print(x)
data = sum([1, 2, 3, 4, 5])
print(f'Sum: {data}')
