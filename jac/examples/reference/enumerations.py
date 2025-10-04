from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
from enum import Enum, auto
from enum import unique

@unique
@_jl.sem('', {'RED': '', 'GREEN': '', 'BLUE': ''})
class Color(Enum):
    RED = 1
    GREEN = 2
    BLUE = 3

@_jl.sem('', {'ADMIN': '', 'USER': '', 'GUEST': ''})
class Role(Enum):
    ADMIN = 'admin'
    USER = 'user'
    GUEST = 'guest'
    print('Initializing role system..')

    def foo() -> str:
        return 'Accessing privileged Data'

@_jl.sem('', {'PENDING': '', 'ACTIVE': '', 'INACTIVE': ''})
class Status(Enum):
    PENDING = 0
    ACTIVE = 1
    INACTIVE = 2

@_jl.sem('', {'LOW': '', 'MEDIUM': '', 'HIGH': ''})
class Priority(Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3

    def get_priority_name(self):
        return self.name.lower()
print(Color.RED.value, Role.foo())
print(Status.ACTIVE)
