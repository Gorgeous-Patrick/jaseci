from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
print('Hello world!')
print(type('Welcome'))
result = (lambda x: x + 10)((lambda x: x * 2)(5))
print(result)
