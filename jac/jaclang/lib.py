"""Jac Library - Auto-generated function interface."""

import inspect

from jaclang.runtimelib.machine import JacMachineInterface

# Automatically expose all static methods from JacMachineInterface as module-level functions
__all__ = []

for name, method in inspect.getmembers(JacMachineInterface, predicate=inspect.ismethod):
    if not name.startswith("_"):  # Skip private methods
        globals()[name] = method
        __all__.append(name)

for name, _ in inspect.getmembers(JacMachineInterface, predicate=inspect.isfunction):
    if not name.startswith("_") and name not in globals():
        globals()[name] = getattr(JacMachineInterface, name)
        if name not in __all__:
            __all__.append(name)

# Sort __all__ for cleaner output
__all__.sort()
