"""Custome Size calculator."""

def _calculate_size_single(obj, name: str):
      if isinstance(obj, int):
        return 8 # Assuming that it is int8
      elif isinstance(obj, float):
        return 8
      elif isinstance(obj, bool):
        return 1
      else:
        # Split the name in camel case
        size_name = name.lower().split('_')[-1]
        return int(size_name)

def calculate_size(obj) -> int:
      attrs = [(name, getattr(obj,name)) for name in dir(obj) if not name.startswith("_") and not callable(getattr(obj,name))]
      names = [name for name, _ in attrs]
      return sum([_calculate_size_single(attr, name) for name, attr in attrs])
