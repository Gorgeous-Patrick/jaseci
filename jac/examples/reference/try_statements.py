from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
try:
    print('Result', 5 / 0)
except Exception as e:
    print(e)
try:
    x = int('not a number')
except ValueError as ve:
    print('ValueError:', ve)
except TypeError as te:
    print('TypeError:', te)
except Exception as e:
    print('Other exception:', e)
try:
    result = 10 / 2
except ZeroDivisionError:
    print('Cannot divide by zero')
else:
    print('Division successful:', result)
try:
    f = None
except FileNotFoundError:
    print('File not found')
finally:
    print('Cleanup: finally always runs')
try:
    data = [1, 2, 3]
    print(data[1])
except IndexError as ie:
    print('Index error:', ie)
else:
    print('Access successful')
finally:
    print('Cleanup complete')
