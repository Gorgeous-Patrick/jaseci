"""Define some data structures for DPU simulation runtime."""

import struct
from dataclasses import dataclass


@dataclass
class ContainerObject:
    """Container object to store walker state on DPU."""

    walker_ptr: int
    walker_size: int
    node_ptr: int
    node_size: int
    edge_num: int

    def get_byte_stream(self) -> bytes:
        """Get the byte stream of the container object."""
        return struct.pack(
            "<QQQQQ",
            self.walker_ptr,
            self.walker_size,
            self.node_ptr,
            self.node_size,
            self.edge_num,
        )

    def get_type_def(self) -> str:
        """Get the C type definition of the container object."""
        return "uint64_t walker_ptr; uint64_t walker_size; uint64_t node_ptr; uint64_t node_size; uint64_t edge_num;"


@dataclass
class Container:
    """Container to store multiple container objects."""

    container_objects: list[ContainerObject]

    def get_byte_stream(self) -> bytes:
        """Get the byte stream of the container object."""
        return b"".join([obj.get_byte_stream() for obj in self.container_objects])

    def get_type_def(self) -> str:
        """Get the C type definition of the container object."""
        return f"ContainerObject container_objects[{len(self.container_objects)}];"


@dataclass
class Metadata:
    """Metadata for DPU execution."""

    extra_mram_space: int  # MRAM space unused by objects
    walker_num: int
    walker_container_ptrs: list[int]  # Pointers to each walker's container

    def get_byte_stream(self) -> bytes:
        """Get the C type definition of the metadata object."""
        return struct.pack("<QQ", self.extra_mram_space, self.walker_num) + b"".join(
            struct.pack("<Q", ptr) for ptr in self.walker_container_ptrs
        )

    def get_type_def(self) -> str:
        """Get the C type definition of the metadata object."""
        return f"uint64_t extra_mram_space; uint64_t walker_num; uint64_t walker_container_ptrs[{self.walker_num}];"
