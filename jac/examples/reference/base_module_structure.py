"""Base module structure: Module and element docstrings, entry points.

This is the module-level docstring.
It describes the purpose of the entire module.
"""
from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
import math
global_value: int = 42

@_jl.sem('', {'value': 'A value stored in MyObject'})
class MyObject(_jl.Obj):
    value: int = 0

def add(a: int, b: int) -> int:
    return a + b
print('Default entry:', add(5, 8))
if __name__ == '__main__':
    print('Named entry:', add(1, 2))

def python_multiply(x, y):
    return x * y

@_jl.jac_test
def test_basic_test(_check) -> None:
    result = add(2, 3)
    _check.assertEqual(result, 5)
