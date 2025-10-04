from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
day = ' sunday'
match day:
    case 'monday':
        print('confirmed')
    case _:
        print('other')
