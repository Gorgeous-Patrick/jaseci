from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
a = 5
X = 10
y = 15
z = 20

class Myobj(_jl.Obj):
    pass
if __name__ == '__main__':
    print(a, X, y, z)
