"""
Type system evaluator for JacLang.

PyrightReference:
    packages/pyright-internal/src/analyzer/typeEvaluator.ts
    packages/pyright-internal/src/analyzer/typeEvaluatorTypes.ts
"""

from dataclasses import dataclass

import jaclang.compiler.unitree as uni
from jaclang.compiler.type_system import types

from .types import TypeBase


@dataclass
class PrefetchedTypes:
    """Types whose definitions are prefetched and cached by the type evaluator."""

    none_type_class: TypeBase | None = None
    object_class: TypeBase | None = None
    type_class: TypeBase | None = None
    union_type_class: TypeBase | None = None
    awaitable_class: TypeBase | None = None
    function_class: TypeBase | None = None
    method_class: TypeBase | None = None
    tuple_class: TypeBase | None = None
    bool_class: TypeBase | None = None
    int_class: TypeBase | None = None
    str_class: TypeBase | None = None
    dict_class: TypeBase | None = None
    module_type_class: TypeBase | None = None
    typed_dict_class: TypeBase | None = None
    typed_dict_private_class: TypeBase | None = None
    supports_keys_and_get_item_class: TypeBase | None = None
    mapping_class: TypeBase | None = None
    template_class: TypeBase | None = None


class TypeEvaluator:
    """Type evaluator for JacLang."""

    def __init__(self, builtins_module: uni.Module) -> None:
        """Initialize the type evaluator with prefetched types.

        Implementation Note:
        --------------------
        Pyright is prefetching the builtins when an evaluation is requested
        on a node and from that node it does lookup for the builtins scope
        and does the prefetch once, however if we forgot to call prefetch
        in some place then it will not be available in the evaluator, So we
        are prefetching the builtins at the constructor level once.
        """
        self.builtins_module = builtins_module
        self.prefetch = self._prefetch_types()

    # Pyright equivalent function name = getEffectiveTypeOfSymbol.
    def get_type_of_symbol(self, symbol: uni.Symbol) -> TypeBase:
        """Return the effective type of the symbol."""
        decl_type = self._get_declared_type_of_symbol(symbol)
        if decl_type is not None:
            return decl_type
        return self._get_inferred_type_of_symbol(symbol)

    def get_type_of_class(self, node: uni.Archetype) -> TypeBase:
        """Return the effective type of the class."""
        # Is this type already cached?
        if node.name_spec.type is not None:
            return node.name_spec.type

        cls_type = types.ClassType(
            class_name=node.name_spec.sym_name,
            symbol_table=node,
            # TODO: Resolve the base class expression and pass them here.
        )

        # Cache the type, pyright is doing invalidateTypeCacheIfCanceled()
        # we're not doing that any time sooner.
        node.name_spec.type = cls_type
        return cls_type

    def get_type_of_string(self, node: uni.String | uni.MultiString) -> TypeBase:
        """Return the effective type of the string."""
        # FIXME: Strings are a type of LiteralString type:
        # "foo" is not `str` but Literal["foo"], however for now we'll
        # not considering that and make it work and will implement that
        # later.
        #
        # see: getTypeOfString() in pyright (it requires parsing the sub
        # file of the typing module).
        assert self.prefetch.str_class is not None
        return self.prefetch.str_class

    def get_type_of_int(self, node: uni.Int) -> TypeBase:
        """Return the effective type of the int."""
        assert self.prefetch.int_class is not None
        return self.prefetch.int_class

    # Pyright equivalent function name = getTypeOfExpression();
    def get_type_of_expression(self, node: uni.Expr) -> TypeBase:
        """Return the effective type of the expression."""
        # If it's alreay "cached" return it.
        if node.type is not None:
            return node.type

        result = self._get_type_of_expression_core(node)
        # If the context has an expected type, pyright does a compatibility and set
        # a diagnostics here, I don't understand why that might be necessary here.

        node.type = result  # Cache the result
        return result

    # Comments from pyright:
    # // Determines if the source type can be assigned to the dest type.
    # // If constraint are provided, type variables within the destType are
    # // matched against existing type variables in the map. If a type variable
    # // in the dest type is not in the type map already, it is assigned a type
    # // and added to the map.
    def assign_type(self, src_type: TypeBase, dest_type: TypeBase) -> bool:
        """Assign the source type to the destination type."""
        if types.TypeCategory.Unknown in (src_type.category, dest_type.category):
            # NOTE: For now if we don't have the type info, we assume it's compatible.
            # For strict mode we should disallow usage of unknown unless explicitly ignored.
            return True
        # FIXME: This logic is not valid, just here as a stub.
        return src_type == dest_type

    def _prefetch_types(self) -> "PrefetchedTypes":
        """Return the prefetched types for the type evaluator."""
        return PrefetchedTypes(
            # TODO: Pyright first try load NoneType from typeshed and if it cannot
            # then it set to unknown type.
            none_type_class=types.UnknownType(),
            # object_class=
            # type_class=
            # union_type_class=
            # awaitable_class=
            # function_class=
            # method_class=
            # tuple_class=
            # bool_class=
            int_class=self._get_builtin_type("int"),
            str_class=self._get_builtin_type("str"),
            # dict_class=
            # module_type_class=
            # typed_dict_class=
            # typed_dict_private_class=
            # supports_keys_and_get_item_class=
            # mapping_class=
            # template_class=
        )

    def _get_builtin_type(self, name: str) -> TypeBase:
        """Return the built-in type with the given name."""
        if (symbol := self.builtins_module.lookup(name)) is not None:
            return self.get_type_of_symbol(symbol)
        return types.UnknownType()

    # This function is a combination of the bellow pyright functions.
    #  - getDeclaredTypeOfSymbol
    #  - getTypeForDeclaration
    def _get_declared_type_of_symbol(self, symbol: uni.Symbol) -> TypeBase | None:
        """Return the declared type of the symbol."""
        node = symbol.decl.name_of
        match node:
            case uni.Archetype():
                return self.get_type_of_class(node)

            # This actually defined in the function getTypeForDeclaration();
            # Pyright has DeclarationType.Variable.
            case uni.Name():
                if isinstance(node.parent, uni.Assignment):
                    if node.parent.type_tag is not None:
                        annotation_type = self.get_type_of_expression(
                            node.parent.type_tag.tag
                        )
                        # FIXME:
                        # In pyright types.ts there is a flag enum `export const enum TypeFlags {`
                        # That defines a class type can be instantiated or instance of the same type
                        # and call convertToInstance() to create an instance type of the type.
                        #
                        # example:
                        #   foo = 42  # <-- Here type of foo is `int` class
                        #   foo = int # <-- Here type of foo is `type[int]`, for pyright it's `int`
                        #                   that can be instanciated.
                        #
                        #  foo: int = 42
                        #       ^^^------- Here the type of the expression `int` is `type[int]`
                        #                  So we need to call convertToInstance().
                        return annotation_type

                    else:  # Assignment without a type annotation.
                        return None  # No explicit type declaration.

            # TODO: Implement for functions, parameters, explicit type
            # annotations in assignment etc.
        return None

    def _get_inferred_type_of_symbol(self, symbol: uni.Symbol) -> TypeBase:
        """Return the inferred type of the symbol."""
        # TODO: Eval the expression to get the inferred type and return.
        return types.UnknownType()

    # Pyright equivalent function name = getTypeOfExpressionCore();
    def _get_type_of_expression_core(self, expr: uni.Expr) -> TypeBase:
        """Core function to get the type of the expression."""
        match expr:

            case uni.String() | uni.MultiString():
                return self.get_type_of_string(expr)

            case uni.Int():
                return self.get_type_of_int(expr)

            case uni.Name():
                if symbol := expr.sym_tab.lookup(expr.value, deep=True):
                    return self.get_type_of_symbol(symbol)
            # TODO: More expressions.
        return types.UnknownType()
