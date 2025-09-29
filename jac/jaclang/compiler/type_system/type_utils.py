"""Functions that operate on Type objects.

PyrightReference: packages/pyright-internal/src/analyzer/typeUtils.ts
"""

import jaclang.compiler.unitree as uni
from jaclang.compiler.constant import Tokens as Tok
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


# In pyright, this class lives in the parameterUtils.ts however we're
# putting it here for now and if the scale of the code grows we can
# split it into a separate file.
class ParamAssignmentTracker:
    """Tracks parameter assignments for function calls.

    This class helps in tracking which parameters have been matched
    with arguments in a function call. It supports positional, named,
    *args, and **kwargs arguments.
    """

    def __init__(self, params: list[types.Parameter]) -> None:
        """Initialize obviously."""
        self.params = params
        self.curr_param_idx = 0
        self.matched_params: set[types.Parameter] = set()

        # Quick access to vararg and kwarg parameters
        self.varargs: types.Parameter | None = None
        self.kwargs: types.Parameter | None = None

        # "Cache" vararg and kwarg parameters for quick access
        for param in self.params:
            if param.param_kind == types.ParamKind.VARARG:
                self.varargs = param
            elif param.param_kind == types.ParamKind.KWARG:
                self.kwargs = param

    def lookup_named_parameter(self, param_name: str) -> types.Parameter | None:
        """Lookup a named parameter by name and if any match is found we mark it as such."""
        for param in self.params:
            # User try to pass a positional only parameter with a name, should be an error.
            if (param.param_kind == types.ParamKind.POSONLY) and (
                param_name == param.name
            ):
                self.matched_params.add(param)
                raise Exception(
                    f"Positional only parameter '{param.name}' cannot be matched with a named argument"
                )
            if param.param_kind not in (types.ParamKind.NORMAL, types.ParamKind.KWONLY):
                continue
            if param.name == param_name:
                if param in self.matched_params:
                    raise Exception(f"Parameter '{param.name}' already matched")
                self.matched_params.add(param)
                return param
        # If we reached here, there is no named parameter to match with
        # however if we have **kwargs, we can match it with that, if that
        # also None, it'll return None indicating no match.
        return self.kwargs

    def _mark_all_named_params_as_matched(self) -> None:
        """Mark all named parameters as matched."""
        for param in self.params:
            if param.param_kind in (
                types.ParamKind.NORMAL,
                types.ParamKind.KWONLY,
                types.ParamKind.KWARG,
            ):
                self.matched_params.add(param)

    def _mark_all_positional_params_as_matched(self) -> None:
        """Mark all positional parameters as matched."""
        for param in self.params:
            if param.param_kind in (
                types.ParamKind.POSONLY,
                types.ParamKind.NORMAL,
                types.ParamKind.VARARG,
            ):
                self.matched_params.add(param)
        self.curr_param_idx = -1

    def match_named_argument(self, arg: uni.KWPair) -> types.Parameter | None:
        """Match a named argument to a parameter."""
        if arg.key is None:
            # **{} <- This can be matched with any named parameter
            # in the current parameter list.
            self._mark_all_named_params_as_matched()
            return None
        else:
            if param := self.lookup_named_parameter(arg.key.sym_name):
                return param
            raise Exception(
                f"Named argument '{arg.key.sym_name}' does not match any parameter"
            )

    def match_positional_argument(self, arg: uni.Expr) -> types.Parameter | None:
        """Match a positional argument to a parameter."""
        # NOTE: The curr_param_idx can be -1 only when a unpack (*expr) is passed
        # at that point there is no reliable way to match the remaining positional
        # arguments after the unpack, so we either match with *args or not match with
        # anything.
        if self.curr_param_idx == -1:
            return self.varargs

        if isinstance(arg, uni.UnaryExpr) and arg.op.value == Tok.STAR_MUL:
            self._mark_all_positional_params_as_matched()
            return None
        else:
            if self.curr_param_idx < len(self.params):
                param = self.params[self.curr_param_idx]
                if param.param_kind == types.ParamKind.VARARG:
                    self.matched_params.add(param)
                    return param
                if param.param_kind in (
                    types.ParamKind.NORMAL,
                    types.ParamKind.POSONLY,
                ):
                    self.curr_param_idx += 1
                    self.matched_params.add(param)
                    return param

            # If we reached here, there is no parameter to match with
            raise Exception("Too many positional arguments")

    def get_unmatched_required_params(self) -> list[types.Parameter]:
        """Check if there are any unmatched required parameters."""
        ret: list[types.Parameter] = []
        for param in self.params:
            if (
                param not in self.matched_params
                and param.default_value is None
                and param.param_kind
                not in (types.ParamKind.VARARG, types.ParamKind.KWARG)
            ):
                ret.append(param)
        return ret
