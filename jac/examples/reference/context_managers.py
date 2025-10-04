from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
import typing
with open(__file__, 'r') as file:
    pass

class Resource:

    def __enter__(self: Resource) -> Resource:
        print('Acquiring resource')
        return self

    def __exit__(self: Resource, exc_type: typing.Optional[Type[BaseException]], exc_val: typing.Optional[BaseException], exc_tb: typing.Optional[typing.TracebackType]) -> None:
        print('Releasing resource')
with Resource() as r:
    print('Using resource')
