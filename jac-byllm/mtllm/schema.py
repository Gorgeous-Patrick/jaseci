"""Schema generation for OpenAI compatible APIs.

This module provides functionality to generate JSON schemas for classes and types
and to validate instances against these schemas.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Callable, get_args, get_origin

from pydantic import TypeAdapter


# The OpenAI Schema only expect "object" as the root level type
# and any primitive will have errors with schema validation.
# So we convert primitive types to their object equivalents.
@dataclass
class _WrappedForSchema:
    """Base class of types wrapped for schema."""


@dataclass
class _WrappedDictionary(_WrappedForSchema):
    """A wrapper for dictionary types."""


def _make_type_wrapper(ty: type) -> type[_WrappedForSchema]:
    @dataclass
    class WrappedType(_WrappedForSchema):
        value: ty  # type: ignore

    return WrappedType


def _make_type_wrapper_dict(ty_key: type, ty_value: type) -> type[_WrappedDictionary]:
    @dataclass
    class KVPair(_WrappedForSchema):
        key: ty_key  # type: ignore
        value: ty_value  # type: ignore

    @dataclass
    class Dictionary(_WrappedDictionary):
        kv_pairs: list[KVPair]

    return Dictionary


def wrap_to_schema_type(ty: type | None) -> type | None:
    """Wrap primitive types to their object equivalents."""
    # TODO: We can actually support objects by setting the resp_type to "json_object",
    # instead of "json_schema" and make it work.
    if ty in (list, dict, object, tuple):
        raise ValueError(
            "For list, dict you must specify the type annotation for the llm to construct the object properly. "
            "For example: `list[str]` or `dict[str, int]`. And object type should not be used."
        )

    # If string we return None, that makes no schema and by default
    # the LLM will return a string.
    if ty is None or ty is str:
        return None

    # Enums schema are generated as primitive types so we also need to wrap
    # them into an object.
    if issubclass(ty, Enum) or get_origin(ty) == list or ty in (str, int, float, bool):
        return _make_type_wrapper(ty)

    if get_origin(ty) == dict:
        return _make_type_wrapper_dict(*get_args(ty))

    return ty


def unwrap_from_schema_type(inst: object) -> object:
    """Unwraps wrapped types (above function) back to their original types."""
    if isinstance(inst, _WrappedDictionary):
        ret = {kv_pair.key: kv_pair.value for kv_pair in inst.kv_pairs}  # type: ignore
        return ret
    if isinstance(inst, _WrappedForSchema):
        return inst.value  # type: ignore
    return inst


def _type_to_schema(type: object) -> dict[str, object]:
    """Return the JSON schema for the given class."""
    schema = TypeAdapter(type).json_schema()

    defs: dict[str, object] = schema.get("$defs", {})  # type: ignore

    # Since OpenAI schema only supports a subset of the JSON schema, the
    # Nested types needs to be fixed like this.
    def fix_schema(schema: object) -> object:
        """Resolve references in the schema."""
        if isinstance(schema, dict):
            if "$ref" in schema:
                ref: str = schema["$ref"]
                return defs[ref.split("/")[-1]]
            for key, value in schema.items():
                schema[key] = fix_schema(value)
            if "properties" in schema and schema.get("type") == "object":
                schema["additionalProperties"] = False
        elif isinstance(schema, list):
            for i, item in enumerate(schema):
                schema[i] = fix_schema(item)
        return schema

    schema: dict[str, object] = fix_schema(schema)  # type: ignore
    schema.pop("$defs", None)
    return schema


def resp_type_schema(resp_type: type) -> dict[str, object]:
    """Return the JSON schema for the response type."""
    return {
        "type": "json_schema",
        "json_schema": {
            "name": resp_type.__name__,
            "schema": _type_to_schema(resp_type),
            "strict": True,
        },
    }


def tool_type_schema(
    func: Callable, description: str, params_desc: dict[str, str]
) -> dict[str, object]:
    """Return the JSON schema for the tool type."""
    schema = _type_to_schema(func)
    schema.pop("type", None)
    properties: dict[str, object] = schema.get("properties", {})  # type: ignore
    for param_name, param_info in properties.items():
        param_info["description"] = params_desc.get(param_name, "")  # type: ignore
    return {
        "type": "function",
        "function": {
            "name": func.__name__,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": properties,
            },
        },
        **schema,
    }
