from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
for i in 'ban':
    print(i)
for j in range(1, 3):
    print(j)
k = 1
while k < 3:
    print(k)
    k += 1
for x in [1, 2, 3]:
    print(x)
else:
    print('For loop completed')
for num in range(10):
    if num == 5:
        break
    print(num)
else:
    print("Won't print due to break")
for i in 'ban':
    for j in range(1, 3):
        k = 1
        while k < 3:
            print(i, j, k)
            k += 1
