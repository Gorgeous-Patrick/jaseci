from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Point(_jl.Obj):
    x: float
    y: float
data = Point(x=9, y=0)
match data:
    case Point(int(a), y=0):
        print(f'Point with x={a} and y=0')
    case _:
        print('Not on the x-axis')
