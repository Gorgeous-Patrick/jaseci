from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def myFunc() -> None:
    yield 'Hello'
    yield 91
    yield 'Good Bye'
    yield

def number_generator(n: int) -> None:
    for i in range(n):
        yield i

def yield_from_example() -> None:
    yield from number_generator(3)
    yield from ['a', 'b', 'c']

def conditional_yield(items: list) -> None:
    for item in items:
        if item % 2 == 0:
            yield item
x = myFunc()
for z in x:
    print(z)
print('\nYield from:')
gen = yield_from_example()
for val in gen:
    print(val)
print('\nEven numbers:')
evens = conditional_yield([1, 2, 3, 4, 5, 6])
for num in evens:
    print(num)
