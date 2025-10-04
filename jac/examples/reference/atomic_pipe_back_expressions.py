from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
print('Hello world!')
a = [2, 4, 5, 7, 8]
b = [4, 8, 9, 13, 20]
c = len(a) + len(b)
print(c)
result = (lambda x: x * 3)(10)
print('Result:', result)
