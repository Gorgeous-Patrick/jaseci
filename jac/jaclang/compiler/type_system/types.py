"""Representation of types used during type analysis."""

from __future__ import annotations

# Pyright Reference: packages\pyright-internal\src\analyzer\types.ts
from abc import ABC
from enum import Enum, auto
from pathlib import Path
from typing import ClassVar, TYPE_CHECKING

if TYPE_CHECKING:
    from jaclang.compiler.unitree import UniScopeNode as SymbolTable


class TypeCategory(Enum):
    """Enumeration of type categories."""

    Unbound = auto()  # Name is not bound to a value of any type
    Unknown = auto()  # Implicit Any type
    Never = auto()  # The bottom type, equivalent to an empty union
    Any = auto()  # Type can be anything
    Module = auto()  # Module instance
    Class = auto()  # Class definition
    Function = auto()  # Callable type
    Union = auto()  # Union of two or more other types


class ParameterCategory(Enum):
    """Enumeration of parameter categories."""

    Positional = auto()
    ArgsList = auto()
    KwargsDict = auto()


class TypeBase(ABC):
    """Maps to pyright's TypeBase<T> in the types.ts file.

    This is the base class for all type instance of the jaclang that holds
    information about the type's category and any additional metadata and
    utilities to analyze type information and provide type checking.
    """

    # Each subclass should provide a class-level CATEGORY constant indicating its type category.
    CATEGORY: ClassVar[TypeCategory]

    @property
    def category(self) -> TypeCategory:
        """Returns the category of the type."""
        return self.CATEGORY

    @staticmethod
    def unknown() -> "UnknownType":
        """Return an instance of an unknown type."""
        return UnknownType()


class UnboundType(TypeBase):
    """Represents a type that is not bound to a specific value or context."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Unbound


class UnknownType(TypeBase):
    """Represents a type that is not known or cannot be determined."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Unknown


class NeverType(TypeBase):
    """Represents a type that can never occur."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Never


class AnyType(TypeBase):
    """Represents a type that can be anything."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Any


class ModuleType(TypeBase):
    """Represents a module type."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Module

    def __init__(
        self, mod_name: str, file_uri: Path, symbol_table: SymbolTable
    ) -> None:
        """Initialize the class."""
        self.mod_name = mod_name
        self.file_uri = file_uri
        self.symbol_table = symbol_table


class ClassType(TypeBase):
    """Represents a class type."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Class

    def __init__(
        self,
        class_name: str,
        symbol_table: SymbolTable,
        base_classes: list[TypeBase] | None = None,
    ) -> None:
        """Initialize the class type."""
        self.class_name = class_name
        self.symbol_table = symbol_table
        self.base_classes = base_classes or []


class Parameter:
    """Represents a function parameter."""

    def __init__(
        self, name: str, category: ParameterCategory, param_type: TypeBase | None
    ) -> None:
        """Initialize obviously."""
        self.name = name
        self.category = category
        self.param_type = param_type


class FunctionType(TypeBase):
    """Represents a function type."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Function

    def __init__(
        self,
        func_name: str,
        return_type: TypeBase | None = None,
        parameters: list[Parameter] | None = None,
    ) -> None:
        """Initialize obviously."""
        self.func_name = func_name
        self.return_type = return_type
        self.parameters = parameters or []


class UnionType(TypeBase):
    """Represents a union type."""

    CATEGORY: ClassVar[TypeCategory] = TypeCategory.Union

    def __init__(self, types: list[TypeBase]) -> None:
        """Initialize obviously."""
        self.types = types
