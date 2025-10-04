from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Animal(_jl.Obj):
    species: str
    sound: str

    def __init__(self, species: str, sound: str) -> None:
        self.species = species
        self.sound = sound

class Dog(Animal, _jl.Obj):
    breed: str
    trick: str = _jl.field(init=False)

    def __post_init__(self) -> None:
        self.trick = 'Roll over'
        print('Postinit called')

    def speak(self) -> None:
        print(f'{self.species} says {self.sound}')

    def __init__(self, breed: str) -> None:
        super().__init__(species='Dog', sound='Woof!')
        self.breed = breed

class Cat(Animal, _jl.Obj):

    def __init__(self, fur_color: str) -> None:
        super().__init__(species='Cat', sound='Meow!')
        self.fur_color = fur_color

class Explorer(_jl.Walker):

    @_jl.entry
    def explore(self, here: _jl.Root) -> None:
        print(f'Current node (here): {here}')
        print(f'Current walker (visitor): {visitor}')
        print(f'Root node: {_jl.root()}')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class Location(_jl.Node):
    name: str

    @_jl.entry
    def greet(self, visitor: Explorer) -> None:
        print(f'At location: {here.name}')
dog = Dog(breed='Labrador')
cat = Cat(fur_color='Tabby')
dog.speak()
