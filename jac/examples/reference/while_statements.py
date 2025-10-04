from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
x = 0
while x < 5:
    print(x)
    x += 1
count = 0
while count < 3:
    print(f'Count: {count}')
    count += 1
else:
    print('While loop completed normally')
i = 0
while i < 10:
    if i == 5:
        break
    print(f'i = {i}')
    i += 1
else:
    print("This won't print because of break")
