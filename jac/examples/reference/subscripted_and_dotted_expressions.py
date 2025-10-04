from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Sample(_jl.Obj):
    my_list: list = _jl.field(factory=lambda: [1, 2, 3])
    my_dict: dict = _jl.field(factory=lambda: {'name': 'John', 'age': 30})
first, second = (Sample().my_list[2], Sample().my_dict['name'])
print(first, second)
