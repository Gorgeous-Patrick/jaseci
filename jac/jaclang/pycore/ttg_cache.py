from __future__ import annotations

from collections.abc import Callable, Iterable
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


class Cache(Generic[K, V]):
    def __init__(self, cache_size: int):
        self.lru: LRUCache[K, V] = LRUCache(cache_size)
        self.database: dict[K, V] = {}
        self.cache_hits = 0
        self.total_accesses = 0

    def write(self, key: K, value: V) -> None:
        evicted = self.lru.put(key, value)
        if evicted is None:
            self.cache_hits += 1
        else:
            old_key, old_value = evicted
            self.database[old_key] = old_value
        self.total_accesses += 1

    def read(self, key: K) -> V:
        cached = self.lru.get(key)
        self.total_accesses += 1
        if cached is not None:
            self.cache_hits += 1
            return cached
        if key not in self.database:
            raise KeyError(f"Key {key!r} not present in backing store")
        value = self.database[key]
        evicted = self.lru.put(key, value)
        if evicted is not None:
            old_key, old_value = evicted
            self.database[old_key] = old_value
        return value

    def prefetch(
        self, keys: Iterable[K], loader: Callable[[K], V] | None = None
    ) -> None:
        """Warm cache entries without mutating hit statistics."""

        for key in keys:
            if self.lru.get(key) is not None:
                continue
            if key in self.database:
                value = self.database[key]
            elif loader is not None:
                value = loader(key)
                self.database[key] = value
            else:
                raise KeyError(f"Cannot prefetch missing key {key!r} without a loader")
            evicted = self.lru.put(key, value)
            if evicted is not None:
                old_key, old_value = evicted
                self.database[old_key] = old_value

    def get_stats(self) -> tuple[int, int]:
        print(
            f"Total Cache Hits: {self.cache_hits}\nTotal Accesses: {self.total_accesses}"
        )
        return self.cache_hits, self.total_accesses
