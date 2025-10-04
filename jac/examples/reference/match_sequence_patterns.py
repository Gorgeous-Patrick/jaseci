from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
data = [1, 2, 3]
match data:
    case [1, 2, 3]:
        print('Matched')
    case _:
        print('Not Found')
