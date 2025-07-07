"""Plugin for Jac's with_llm feature."""

from typing import Callable

from jaclang.runtimelib.machine import hookimpl

from mtllm.llm import Model


class JacMachine:
    """Jac's with_llm feature."""

    @staticmethod
    @hookimpl
    def call_llm(
        model: Model, caller: Callable, args: dict[str | int, object]
    ) -> object:
        """Call JacLLM and return the result."""
        return model.invoke(caller, args)
