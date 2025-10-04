from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
from time import sleep

class A(_jl.Node):
    val: int = 0

    @_jl.entry
    def do(self, visitor) -> None:
        print('Started')
        sleep(2)
        print(visitor)

class B(_jl.Walker):
    name: str

def add(x: int, y: int) -> int:
    print(x)
    z = x + y
    sleep(2)
    print(x)
    return z
t1 = _jl.thread_run(lambda: _jl.spawn(A(), B('Hi')))
task1 = _jl.thread_run(lambda: add(1, 10))
task2 = _jl.thread_run(lambda: add(2, 11))
print('All are started')
res1 = _jl.thread_wait(task1)
res2 = _jl.thread_wait(task2)
print('All are done')
print(res1)
print(res2)
