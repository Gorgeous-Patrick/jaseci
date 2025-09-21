"""Data mapper.

This module is responsible for: 1. Predicting the data access pattern and 2. Calculate the best mapping to PIM
"""

from dataclasses import dataclass  # noqa: F401

from jaclang.compiler import unitree as uni  # noqa: F401

from .partitioner import random_partition  # noqa: F401
from .perf_measure import get_num_dpu_jumps, get_num_dpu_jumps_adaptive  # noqa: F401
from .visit_sequence import VisitInfo, get_visit_sequences  # noqa: F401
from .size_calc import calculate_size # noqa: F401

# from .mapping_phase import get_visit_info, png_gen_networkx   # noqa: F401
