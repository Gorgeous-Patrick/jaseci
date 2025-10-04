from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
x = 'a'
y = 25
print(f'Hello {x} {y} {{This is an escaped curly brace}}')
print(f'Single quoted: {x} and {y}')
person = {'name': 'Jane', 'age': 25}
print(f"Hello, {person['name']}! You're {person['age']} years old.")
print('Escaped braces: {{ and }}')
print(f'Calculation: {5 + 3} = {5 + 3}')
text = 'hello'
print(f'Uppercase: {text.upper()}')
age = 18
print(f'Status: {('Adult' if age >= 18 else 'Minor')}')
name = 'Alice'
score = 95
message = f'\n    Name: {name}\n    Score: {score}\n    Grade: {('A' if score >= 90 else 'B')}\n    '
print(message)
print('This is the first line.\n This is the second line.')
print('This will not print.\r This will be printed')
print('This is \t tabbed.')
print('Line 1\x0cLine 2')
words = ['Hello', 'World!', 'I', 'am', 'a', 'Jactastic!']
print(f'{'\n'.join(words)}')
value = 42
print(f'Value is {f'{value}'}')
pi = 3.14159
