"""Data mapper.

This module is responsible for: 1. Predicting the data access pattern and 2. Calculate the best mapping to PIM
"""

from dataclasses import dataclass  # noqa: F401

from jaclang.compiler import unitree as uni  # noqa: F401

from .access_pattern import (  # noqa: F401
    get_access_pattern,
    get_access_pattern_single_walker,
)
from .partitioner import metis_partition, random_partition  # noqa: F401
from .perf_measure import get_num_dpu_jumps  # noqa: F401
from .static_phase import VisitInfo  # noqa: F401
from .size_calc import calculate_size # noqa: F401

# from .mapping_phase import get_visit_info, png_gen_networkx   # noqa: F401
