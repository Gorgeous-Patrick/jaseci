from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
from enum import Enum, auto
c = (3, 4, 5)
list1 = [2, 3, 4, 5]
a = 'abcde....'
print('String:', a)
b = True
c = False
print('Bool:', b, c)
n = None
print('None:', n)
decimal = 42
print('Decimal int:', decimal)
binary = 12
print('Binary 0b1100:', binary)
octal = 493
print('Octal 0o755:', octal)
hexadecimal = 255
print('Hex 0xFF:', hexadecimal)
float_val = 3.14
scientific = 15000000000.0
print('Float:', float_val, scientific)
ellipsis = ...
print('Ellipsis:', ellipsis)
result = (5 + 3) * 2
print('Parenthesized:', result)
variable_name = 100
print('Named ref:', variable_name)
string_type = str
int_type = int
print('Builtin types:', string_type, int_type)
tuple_val = (1, 2, 3)
list_val = [1, 2, 3]
dict_val = {'key': 'value'}
set_val = {1, 2, 3}
multistr = 'Hello World'
print('Multistring:', multistr)
name = 'Alice'
fstr = f'Hello {name}'
print('F-string:', fstr)

@_jl.sem('', {'aa': '', 'y': ''})
class x(Enum):
    aa = 67
    y = 'aaa' + f'b{aa}bbcc'
print(x.y.value)
