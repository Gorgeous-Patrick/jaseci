from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def foo() -> int:
    a = 42
    return a

def bar() -> None:
    print('Executing bar')
    return

def get_value(x: int) -> int:
    if x > 0:
        return x * 2
    else:
        return 0

def early_return(flag: bool) -> None:
    if flag:
        return
    print("This won't execute if flag is True")
print('Returned:', foo())
bar()
print('get_value(5):', get_value(5))
print('get_value(-3):', get_value(-3))
early_return(True)
early_return(False)
