from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
a = 8
match a:
    case 7:
        print('doable')
    case _:
        print('Undoable')
value = 15
match value:
    case x if x < 10:
        print('Less than 10')
    case x if x < 20:
        print('Between 10 and 20')
    case _:
        print('20 or greater')
result = 'success'
match result:
    case 'success':
        print('Operation succeeded')
        print('Logging success')
        status = 200
    case 'error':
        print('Operation failed')
        print('Logging error')
        status = 500
    case _:
        print('Unknown result')
        status = 0
data = [1, 2, 3]
match data:
    case [x]:
        print(f'Single element: {x}')
    case [x, y]:
        print(f'Two elements: {x}, {y}')
    case [x, y, z]:
        print(f'Three elements: {x}, {y}, {z}')
    case _:
        print('More than three elements')
