from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
x = [2, 4, 5, 7, 9]
print('Before Delete:', x)
_jl.destroy([x[3]])
del x[3]
print('After Delete:', x)
y = 100
print('y before delete:', y)
_jl.destroy([y])
del y
d = {'a': 1, 'b': 2, 'c': 3}
print('Dict before delete:', d)
_jl.destroy([d['b']])
del d['b']
print('Dict after delete:', d)

class MyClass(_jl.Obj):
    value: int = 42
instance = MyClass()
print('Attribute before delete:', instance.value)
_jl.destroy([instance.value])
del instance.value
lst = [1, 2, 3, 4, 5]
_jl.destroy([lst[1]])
del lst[1]
_jl.destroy([lst[2]])
del lst[2]
print('After multiple deletes:', lst)
numbers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
_jl.destroy([numbers[2:5]])
del numbers[2:5]
print('After slice delete:', numbers)
