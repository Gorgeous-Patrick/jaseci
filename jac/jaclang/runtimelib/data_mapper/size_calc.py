"""Custome Size calculator."""

def _calculate_size_single(obj):
      if isinstance(obj, str):
        return len(obj) + 1
      elif isinstance(obj, int):
        return 8 # Assuming that it is int8
      elif isinstance(obj, float):
        return 8
      return 0

def calculate_size(obj):
      attrs = [getattr(obj,name) for name in dir(obj) if not name.startswith("_")]
      return sum([_calculate_size_single(attr) for attr in attrs])
