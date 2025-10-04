from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
x = 'Jaclang '

def outer_func() -> None:
    global x
    x = 'Jaclang is '
    y = 'Awesome'
    z = 'Language'

    def inner_func() -> tuple[str, str]:
        nonlocal y
        y = 'Fantastic'
        return (x, y)
    print(x, y)
    print(inner_func())
a = 1
b = 2
c = 3

def modify_globals() -> None:
    global a
    global b
    global c
    a = 10
    b = 20
    c = 30

def nested_scope() -> None:
    var1 = 'outer1'
    var2 = 'outer2'
    var3 = 'outer3'

    def inner() -> None:
        nonlocal var1
        nonlocal var2
        nonlocal var3
        var1 = 'inner1'
        var2 = 'inner2'
        var3 = 'inner3'
    print('Before inner:', var1, var2, var3)
    inner()
    print('After inner:', var1, var2, var3)
outer_func()
print('Before modify_globals:', a, b, c)
modify_globals()
print('After modify_globals:', a, b, c)
nested_scope()
