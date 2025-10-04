from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
import random

class TestObj(_jl.Obj):
    x: int = _jl.field(factory=lambda: random.randint(0, 15))
    y: int = _jl.field(factory=lambda: random.randint(0, 15))
    z: int = _jl.field(factory=lambda: random.randint(0, 15))
random.seed(42)
apple = []
i = 0
while i < 100:
    apple.append(TestObj())
    i += 1
print(_jl.filter(items=apple, func=lambda i: i.x >= 0 and i.x <= 15) == apple)

class MyObj(_jl.Obj):
    apple: int = 0
    banana: int = 0
x = MyObj()
y = MyObj()
mvar = _jl.assign([x, y], (('apple', 'banana'), (5, 7)))
print(mvar)
