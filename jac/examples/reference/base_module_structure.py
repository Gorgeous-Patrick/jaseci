"""A Docstring can be added the head of any module.

Any element in the module can also have a docstring.
If there is only one docstring before the first element,
it is assumed to be a module docstring.
"""
from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def add(a: int, b: int) -> int:
    """A docstring for add function"""
    return a + b

def subtract(a: int, b: int) -> int:
    return a - b
if __name__ == '__main__':
    print(add(1, subtract(3, 1)))
