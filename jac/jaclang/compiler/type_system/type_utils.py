"""Functions that operate on Type objects.

PyrightReference: packages/pyright-internal/src/analyzer/typeUtils.ts
"""

from jaclang.compiler.unitree import Symbol

from . import types


class ClassMember:
    """Represents a member of a class."""

    def __init__(self, symbol: Symbol, class_type: types.ClassType) -> None:
        """Initialize obviously."""
        self.symbol = symbol
        self.class_type = class_type

        # True if it is an instance or class member; it can be both a class and
        # an instance member in cases where a class variable is overridden
        # by an instance variable
        self.is_instance_member = True
        self.is_class_member = False

        # Is the member in __slots__?
        self.is_slots_member = False

        # True if explicitly declared as "ClassVar" and therefore is
        # a type violation if it is overwritten by an instance variable
        self.is_class_var = False

        # True if the member is read-only, such as with named tuples
        # or frozen dataclasses.
        self.is_read_only = False

        # True if member has declared type, false if inferred
        self.is_type_declared = False

        # True if member lookup skipped an undeclared (inferred) type
        # in a subclass before finding a declared type in a base class
        self.skipped_undeclared_type = False


def compute_mro_linearization(cls: types.ClassType) -> None:
    """Compute the method resolution order (MRO) for a class type.

    This uses the C3 linearization algorithm to compute the MRO.
    See https://www.python.org/download/releases/2.3/mro/
    """
    if cls.shared.mro:
        return

    # FIXME: This is an ad-hoc implementation to make the MRO works
    # and it'll cover the 90% or more of the user cases.

    # Computer MRO for base classes first
    cls.shared.mro.append(cls)
    for base in cls.shared.base_classes:
        if isinstance(base, types.ClassType):
            compute_mro_linearization(base)

    # Then add base classes and their MROs
    for base in cls.shared.base_classes:
        if isinstance(base, types.ClassType):
            for mro_cls in base.shared.mro:
                if mro_cls not in cls.shared.mro:
                    cls.shared.mro.append(mro_cls)
