from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
a: float = 9.2
b: int = 44
c: list = [2, 4, 6, 10]
d: dict = {'name': 'john', 'age': 28}
e: tuple = ('jaseci', 5, 4, 14)
f: bool = True
g: str = 'Jaseci'
h: set = {5, 8, 12, 'unique'}
i: bytes = b'binary data'
j: any = 'can be anything'
k: type = str
print('float:', type(a), a)
print('int:', type(b), b)
print('list:', type(c), c)
print('dict:', type(d), d)
print('tuple:', type(e), e)
print('bool:', type(f), f)
print('str:', type(g), g)
print('set:', type(h), h)
print('bytes:', type(i), i)
print('any:', type(j), j)
print('type:', type(k), k)

def typed_func(x: int, y: float, z: str) -> tuple:
    return (x, y, z)
result = typed_func(1, 2.5, 'test')
print('Typed function result:', result)
var1: list = [1, 2, 3]
var2: dict = {}
var3: set = {1, 2}
var4: bytes = b'hello'
var5: any = 42
var6: type = int
print('All types demonstrated')
