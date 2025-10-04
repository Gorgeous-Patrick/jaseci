from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
for i in range(9):
    if i > 2:
        print('loop is stopped!!')
        break
    print(i)
for j in 'WIN':
    if j == 'W':
        continue
    print(j)

class SkipWalker(_jl.Walker):

    @_jl.entry
    def process(self, here) -> None:
        pass
count = 0
while True:
    count += 1
    if count > 5:
        break
    print(f'Count: {count}')
n = 0
while n < 10:
    n += 1
    if n % 2 == 0:
        continue
    print(f'Odd: {n}')
for x in range(3):
    for y in range(3):
        if x == y == 1:
            print(f'Breaking at ({x}, {y})')
            break
        print(f'({x}, {y})')
