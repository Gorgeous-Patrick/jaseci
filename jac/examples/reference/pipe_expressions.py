from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def square(x: int) -> int:
    return x ** 2

def double(x: int) -> int:
    return x * 2

def increment(x: int) -> int:
    return x + 1
number = 5
result = square(number)
print(result)
data = [1, 2, 3, 4, 5]
total = sum(data)
print(f'Sum: {total}')
x = (lambda n: n * 3)(10)
print(x)
