from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
if 5 > 4:
    print('5 > 4: True')
if 5 >= 5:
    print('5 >= 5: True')
if 3 < 10:
    print('3 < 10: True')
if 3 <= 3:
    print('3 <= 3: True')
if 5 == 5:
    print('5 == 5: True')
if 'a' != 'b':
    print("'a' != 'b': True")
a = [1, 2, 3]
b = [1, 2, 3]
c = a
print('a is b:', a is b)
print('a is c:', a is c)
print('a is not b:', a is not b)
print('3 in a:', 3 in a)
print('5 in a:', 5 in a)
print('5 not in a:', 5 not in a)
print('True or False:', True or False)
print('True and False:', True and False)
print('False and False:', False and False)
print('not True:', not True)
print('not False:', not False)
x = 15
if 10 < x < 20:
    print('x is between 10 and 20')
if 0 <= x <= 100:
    print('x is between 0 and 100 inclusive')
age = 25
has_license = True
if age >= 18 and has_license:
    print('Can drive')
if age < 18 or not has_license:
    print('Cannot drive')
else:
    print('Allowed to drive')
if True and True and True:
    print('All true')
if False or False or True:
    print('At least one true')
