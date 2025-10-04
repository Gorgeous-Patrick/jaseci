from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
a = 5
if (b := (a + a // 2)) > 5:
    print('b is greater than 5')
    print(f'b = {b}')
data = [1, 2, 3, 4, 5]
i = 0
while (item := data[i]) if i < len(data) else None:
    print(f'Item: {item}')
    i += 1
    if i >= 3:
        break
values = [1, 2, 3, 4, 5]
result = (x := 10) + 5
print(f'x = {x}, result = {result}')
if (m := 5) and (n := 10):
    print(f'm = {m}, n = {n}')
