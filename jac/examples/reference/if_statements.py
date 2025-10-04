from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
x = 15
if 0 <= x <= 5:
    print('Not Bad')
elif 6 <= x <= 10:
    print('Average')
else:
    print('Good Enough')
if x > 0:
    print('Positive')
if x < 0:
    print('Negative')
elif x == 0:
    print('Zero')
if x < 5:
    print('Very low')
elif x < 10:
    print('Low')
elif x < 15:
    print('Medium')
elif x < 20:
    print('High')
else:
    print('Very high')
if x > 10:
    if x > 20:
        print('Greater than 20')
    else:
        print('Between 10 and 20')
