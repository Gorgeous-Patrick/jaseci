from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
p = print
p('Multiply:', 7 * 2)
p('Division:', 15 / 3)
p('Floor division:', 15 // 3)
p('Modulo:', 17 % 5)
p('Exponentiation:', 2 ** 3)
p('Addition:', 9 + 2)
p('Subtraction:', 9 - 2)
p('Combo:', (9 + 2) * 9 - 2)
x = 5
p('Unary plus:', +x)
p('Unary minus:', -x)
p('Bitwise NOT:', ~x)
p('2 ** 3 ** 2 =', (2 ** 3) ** 2)
result = 2 + 3 * 4 ** 2 - 10 / 2
p('Complex:', result)
p('Chain:', 100 - 50 + 25)
p('Chain mult:', 2 * 3 * 4)
p('17 // 5 =', 17 // 5)
p('17 % 5 =', 17 % 5)
