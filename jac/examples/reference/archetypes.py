from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

def print_base_classes(cls: type) -> type:
    print(f'Base classes of {cls.__name__}: {[c.__name__ for c in cls.__bases__]}')
    return cls

class Animal:
    pass

class Domesticated(_jl.Obj):
    pass

@print_base_classes
class Pet(Animal, Domesticated, _jl.Node):
    pass

class Relationship(_jl.Edge):
    pass

class Connection(_jl.Edge):
    pass

class Person(Animal, _jl.Walker):
    pass

class Feeder(Person, _jl.Walker):
    pass

@print_base_classes
class Zoologist(Feeder, _jl.Walker):
    pass

class MyWalker(_jl.Walker):
    __jac_async__ = True
    pass

class PrivateObject(_jl.Obj):
    pass

class PublicObject(_jl.Obj):
    pass

class ProtectedObject(_jl.Obj):
    pass

class ForwardDeclared:

    def info(self) -> None:
        print('This is a forward-declared class.')

class AbstractNode(_jl.Node):

    def info(self) -> None:
        print('This is an abstract node.')
