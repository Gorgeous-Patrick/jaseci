from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

x = lambda a, b: b + a
print(x(5, 4))
get_five = lambda: 5
print(get_five())
add = lambda x, y: x + y
print(add(3, 7))
get_default = lambda: 42
print(get_default())
multiply = lambda x=2, y=3: x * y
print(multiply())
print(multiply(5))
print(multiply(5, 10))


def sum_all(*args: tuple) -> None:
    return sum(args)


print(sum_all(1, 2, 3, 4, 5))
numbers = [1, 2, 3, 4, 5]
squared = list(map(lambda x: x**2, numbers))
print(squared)
evens = list(filter(lambda x: x % 2 == 0, numbers))
print(evens)
max_val = lambda a, b: a if a > b else b
print(max_val(10, 20))
