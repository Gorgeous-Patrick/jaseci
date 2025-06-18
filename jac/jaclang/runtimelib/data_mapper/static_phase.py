"""Static Analysis."""

from dataclasses import dataclass


@dataclass
class VisitInfo:
    """A struct that stores the visit key information."""

    from_node_type: str
    walker_type: str
    edge_type: str
    async_edge: bool
