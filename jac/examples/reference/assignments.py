from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
a = b = 16
print(a, b)
c = 18
print(c)
x: int = 42
print(x)
y: str
y = 'hello'
print(y)
a >>= 2
print(a)
a <<= 2
print(a)
c //= 4
print(c)
num = 10
num += 5
num -= 3
num *= 2
num /= 2
num %= 3
num **= 2
bits = 15
bits &= 7
bits |= 8
bits ^= 3

def gen() -> None:
    yield 1
    yield 2
x = y = z = 100
print(x, y, z)
result = 5 * (3 + 2)
print(result)
