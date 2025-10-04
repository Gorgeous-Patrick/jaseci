"""This is a member docstring"""
from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Car(_jl.Obj):
    make: str
    model: str
    year: int
    wheels: ClassVar[int] = 4
    internal_id: str = 'car_123'
    manufacturer: str = 'Unknown'
    config: dict = _jl.field(init=False)

    def __post_init__(self) -> None:
        self.config = {'color': 'white', 'sunroof': False}

    def display_car_info(self) -> None:
        print(f'Car Info: {self.year} {self.make} {self.model}')

    @staticmethod
    def get_wheels() -> int:
        return Car.wheels

    def python_method(self):
        return 'This is Python code'

    class Engine:
        horsepower: int
    print('Member-level entry')
car = Car('Toyota', 'Camry', 2020)
car.display_car_info()
print('Number of wheels:', Car.get_wheels())
