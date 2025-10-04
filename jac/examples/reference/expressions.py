from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
x = 1 if 5 / 2 == 1 else 2
print(x)
age = 20
status = 'adult' if age >= 18 else 'minor'
print(status)
score = 85
grade = 'A' if score >= 90 else 'B' if score >= 80 else 'C'
print(grade)
value = max(10, 20) if True else min(10, 20)
print(value)
