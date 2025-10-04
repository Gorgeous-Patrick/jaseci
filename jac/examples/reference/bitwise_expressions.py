from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
p = print
p('5 & 3 =', 5 & 3)
p('5 | 3 =', 5 | 3)
p('5 ^ 3 =', 5 ^ 3)
p('~5 =', ~5)
p('5 << 1 =', 5 << 1)
p('5 >> 1 =', 5 >> 1)
result = (8 | 4) & 12
p('(8 | 4) & 12 =', result)
a = 15
b = 7
p('15 & 7 =', a & b)
p('15 | 7 =', a | b)
p('15 ^ 7 =', a ^ b)
