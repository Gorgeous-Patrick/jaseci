from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
from enum import Enum, auto

@_jl.impl_patch_filename('implementations.jac')
def foo() -> str:
    return 'Hello'

class vehicle(_jl.Obj):
    name: str = 'Car'

@_jl.sem('', {'Small': '', 'Medium': '', 'Large': ''})
class Size(Enum):
    Small = 1
    Medium = 2
    Large = 3
car = vehicle()
print(foo())
print(car.name)
print(Size.Medium.value)
