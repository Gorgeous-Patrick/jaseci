from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
squares = {num: num ** 2 for num in range(1, 6)}
print('Dict compr:', squares)
even_squares_set = {num ** 2 for num in range(1, 11) if num % 2 == 0}
print('Set compr:', even_squares_set)
squares_generator = (num ** 2 for num in range(1, 6))
print('Gen compr:', list(squares_generator))
squares_list = [num ** 2 for num in range(1, 6) if num != 3]
print('List compr:', squares_list)
combined = [x * y for x in [1, 2, 3] for y in [10, 20]]
print('Multiple for:', combined)
filtered = [x for x in range(20) if x % 2 == 0 if x % 3 == 0]
print('Multiple if:', filtered)
dict_literal = {'a': 'b', 'c': 'd'}
print('Dict:', dict_literal)
base_dict = {'x': 1, 'y': 2}
expanded_dict = {**base_dict, 'z': 3}
print('Dict unpack:', expanded_dict)
set_literal = {'a', 'b', 'c'}
print('Set:', set_literal)
tuple_literal = ('a', 'b', 'c')
print('Tuple:', tuple_literal)
list_literal = ['a', 'b', 'c']
print('List:', list_literal)
empty_list = []
empty_dict = {}
empty_tuple = ()
empty_set = set()
print('Empty:', empty_list, empty_dict, empty_tuple, empty_set)
list_with_comma = [1, 2, 3]
dict_with_comma = {'a': 1, 'b': 2}
tuple_with_comma = (1, 2, 3)
print('With comma:', list_with_comma, dict_with_comma, tuple_with_comma)
matrix = [[i * j for j in range(3)] for i in range(3)]
print('Matrix:', matrix)
