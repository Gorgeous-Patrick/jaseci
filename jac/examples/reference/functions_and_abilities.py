from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Divider(_jl.Obj):

    def divide(self, x: float, y: float) -> float:
        return x / y

    def get_default_divisor(self) -> float:
        return 1.0

class Calculator(_jl.Obj):

    @staticmethod
    def multiply(a: float, b: float) -> float:
        return a * b

    @abstractmethod
    def substract(self) -> float:
        pass

    @_jl.impl_patch_filename('functions_and_abilities.jac')
    def add(self, number: float, *a: tuple) -> float:
        return number * sum(a)

    def configure(self, **options: dict) -> dict:
        pass

class Substractor(Calculator, _jl.Obj):

    def substract(self, x: float, y: float) -> float:
        return x - y

class TaskRunner(_jl.Walker):

    @_jl.entry
    def initialize(self, here) -> None:
        print('Walker entered')

    @_jl.exit
    def cleanup(self, here) -> None:
        print('Walker exiting')

async def fetch_data(url: str) -> dict:
    return {'data': 'fetched'}

class AsyncWalker(_jl.Walker):

    @_jl.entry
    async def process(self, here) -> None:
        print('Async processing')

def logger(func: object) -> None:
    return func

@logger
def logged_function(x: int) -> int:
    return x * 2

class AbstractWalker(_jl.Walker):

    @_jl.entry
    @abstractmethod
    def must_implement(self, here) -> None:
        pass
div = Divider()
sub = Substractor()
print(div.divide(55, 11))
print(Calculator.multiply(9, -2))
print(sub.add(5, 20, 34, 56))
print(sub.substract(9, -2))
