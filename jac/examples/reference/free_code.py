from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
import math

class circle(_jl.Obj):

    def __init__(self, radius: float) -> None:
        self.radius = radius

    def area(self) -> float:
        return math.pi * self.radius * self.radius

def foo(n_1: float) -> None:
    return n_1 ** 2
print('Hello World!')
print(foo(7))
print(int(circle(10).area()))
