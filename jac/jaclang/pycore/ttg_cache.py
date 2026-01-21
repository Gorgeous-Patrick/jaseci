from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from typing import Generic, TypeVar

K = TypeVar("K")
V = TypeVar("V")


@dataclass
class Node(Generic[K, V]):
    key: K
    value: V
    prev: Node[K, V] | None = None
    next: Node[K, V] | None = None


class LRUCache(Generic[K, V]):
    """Simple in-memory LRU cache with doubly-linked list eviction."""

    def __init__(self, capacity: int):
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        self._map: dict[K, Node[K, V]] = {}
        self.capacity = capacity
        self.head: Node[K, V] | None = None
        self.tail: Node[K, V] | None = None

    def _add_to_head(self, node: Node[K, V]) -> None:
        node.prev = None
        node.next = self.head
        if self.head:
            self.head.prev = node
        self.head = node
        if self.tail is None:
            self.tail = node

    def _remove_node(self, node: Node[K, V]) -> None:
        if node.prev:
            node.prev.next = node.next
        else:
            self.head = node.next
        if node.next:
            node.next.prev = node.prev
        else:
            self.tail = node.prev
        node.prev = None
        node.next = None

    def _move_to_head(self, node: Node[K, V]) -> None:
        if node is self.head:
            return
        self._remove_node(node)
        self._add_to_head(node)

    def _pop_tail(self) -> Node[K, V] | None:
        if self.tail is None:
            return None
        tail = self.tail
        self._remove_node(tail)
        return tail

    def get(self, key: K) -> V | None:
        node = self._map.get(key)
        if node is None:
            return None
        self._move_to_head(node)
        return node.value

    def put(self, key: K, value: V) -> tuple[K, V] | None:
        node = self._map.get(key)
        if node:
            node.value = value
            self._move_to_head(node)
            return None

        new_node = Node(key=key, value=value)
        self._map[key] = new_node
        self._add_to_head(new_node)

        if len(self._map) > self.capacity:
            tail = self._pop_tail()
            if tail:
                self._map.pop(tail.key, None)
                return tail.key, tail.value
        return None


class Cache(Generic[K]):
    def __init__(self, cache_size: int):
        self.lru: LRUCache[K, bool] = LRUCache(cache_size)
        self.cache_hits = 0
        self.total_accesses = 0

    def _insert(self, key: K) -> K | None:
        evicted = self.lru.put(key, True)
        return evicted[0] if evicted else None

    def read(self, key: K) -> tuple[bool, K | None]:
        """Record an access and return (hit?, evicted key)."""
        print(f"READ: {key}")

        self.total_accesses += 1
        cached = self.lru.get(key)
        if cached is not None:
            self.cache_hits += 1
            return True, None
        evicted_key = self._insert(key)
        return False, evicted_key

    def write(self, key: K) -> K | None:
        """Insert/touch a key; hit if it already resides in cache."""
        print(f"WRITE: {key}")

        self.total_accesses += 1
        cached = self.lru.get(key)
        if cached is not None:
            self.cache_hits += 1
            return None
        return self._insert(key)

    def prefetch(self, keys: Iterable[K]) -> list[K]:
        """Warm cache entries without mutating hit statistics."""
        print(f"PREFETCH: {keys}")

        evicted: list[K] = []
        for key in keys:
            if self.lru.get(key) is not None:
                continue
            popped = self._insert(key)
            if popped is not None:
                evicted.append(popped)
        return evicted

    def get_stats(self) -> tuple[int, int]:
        print(
            f"Total Cache Hits: {self.cache_hits}\nTotal Accesses: {self.total_accesses}"
        )
        return self.cache_hits, self.total_accesses
