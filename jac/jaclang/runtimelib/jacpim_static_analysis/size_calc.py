"""Custome Size calculator."""

from typing import Any


def _calculate_size_single(obj: Any, name: str) -> int:  # noqa: ANN401
    if isinstance(obj, (int, float)):
        return 8  # Assuming that it is int64 or double
    elif isinstance(obj, bool):
        return 1
    else:
        # Split the name in camel case
        size_name = name.lower().split("_")[-1]
        return int(size_name)


def calculate_size(obj: Any) -> int:  # noqa: ANN401
    """Calculate the size of object."""
    attrs = [
        (name, getattr(obj, name))
        for name in dir(obj)
        if not name.startswith("_") and not callable(getattr(obj, name))
    ]
    return sum([_calculate_size_single(attr, name) for name, attr in attrs])
