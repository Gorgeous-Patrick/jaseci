from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
num = 89
match num:
    case 89:
        print('Correct')
    case 8:
        print('Nope')
