from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def foo(value: int) -> None:
    if value < 0:
        raise ValueError('Value must be non-negative')

def bar(x: int) -> None:
    try:
        result = 10 / x
    except ZeroDivisionError as e:
        raise RuntimeError('Division failed') from e

def reraise_example() -> None:
    try:
        raise ValueError('Original error')
    except ValueError:
        print('Caught error, re-raising...')
        raise

def conditional_raise(value: any) -> None:
    if value is None:
        raise ValueError('Value cannot be None')
    if not isinstance(value, int):
        raise TypeError(f'Expected int, got {type(value).__name__}')
    return value * 2
try:
    foo(-1)
except ValueError as e:
    print('Raised:', e)
try:
    bar(0)
except RuntimeError as e:
    print('Runtime error:', e)
try:
    reraise_example()
except ValueError as e:
    print('Re-raised:', e)
try:
    conditional_raise(None)
except ValueError as e:
    print('None value error:', e)
try:
    conditional_raise('not an int')
except TypeError as e:
    print('Type error:', e)
