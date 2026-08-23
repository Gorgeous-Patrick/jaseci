"""Regression tests for TTG cross-root BFS expansion."""

import unittest
from collections.abc import Iterable
from uuid import UUID, uuid4

from jaclang.jac0core.archetype import Root, VisitType
from jaclang.jac0core.ttg import JacTTGGenerator
from jaclang.runtimelib.topology_index import TopologyIndex


class FakeMemory:
    """Minimal memory facade for TTG root-anchor lookups."""

    def __init__(self, anchors: dict[UUID, object]) -> None:
        self.anchors = anchors
        self.prefetched: list[UUID] = []
        self.get_calls: list[UUID] = []
        self.__dict__["__mem__"] = anchors

    def get(self, uid: UUID) -> object:
        self.get_calls.append(uid)
        return self.anchors[uid]

    def prefetch(self, ids: Iterable[UUID]) -> None:
        self.prefetched.extend(ids)


class TTGCrossRootTest(unittest.TestCase):
    def _run_cross_root_ttg(
        self, max_length: int
    ) -> tuple[list[UUID], UUID, UUID, UUID, UUID, FakeMemory]:
        channel = uuid4()
        parent_msg = uuid4()
        reply_msg = uuid4()

        message_root = Root().__jac__
        message_idx = TopologyIndex()
        message_idx.add_node(parent_msg, "Message")
        message_idx.add_node(reply_msg, "Message")
        message_idx.add_edge(reply_msg, parent_msg, "ReplyTo")
        message_root.set_topology_index(message_idx)

        channel_idx = TopologyIndex()
        channel_idx.add_node(channel, "Channel")
        channel_idx.add_node(parent_msg, "Message", owner_root=message_root.id)
        channel_idx.add_edge(parent_msg, channel, "Posted")

        mem = FakeMemory({message_root.id: message_root})
        visits = [
            VisitType("Channel", None, [("Posted", "Message", 1)], True),
            VisitType("Message", None, [("ReplyTo", "Message", 1)], True),
        ]

        self.assertEqual(
            channel_idx.resolve_chain_cross_root(
                mem, {parent_msg}, [("ReplyTo", "Message", 1)]
            ),
            set(),
        )
        self.assertEqual(
            message_idx.resolve_chain({parent_msg}, [("ReplyTo", "Message", 1)]),
            {reply_msg},
        )

        def fake_extract(
            _cls: type[JacTTGGenerator], _warch: object
        ) -> list[VisitType]:
            return visits

        orig = JacTTGGenerator._extract_visits_from_ast
        try:
            JacTTGGenerator._extract_visits_from_ast = classmethod(fake_extract)
            got = JacTTGGenerator.get_ttg_prefetch_list(
                object(), channel, channel_idx, mem, max_length
            )
        finally:
            JacTTGGenerator._extract_visits_from_ast = orig

        return got, channel, parent_msg, reply_msg, message_root.id, mem

    def test_ttg_bfs_uses_foreign_root_index_for_next_visit(self) -> None:
        got, channel, parent_msg, reply_msg, message_root_id, mem = (
            self._run_cross_root_ttg(10)
        )

        self.assertNotIn(channel, got)
        self.assertIn(parent_msg, got)
        self.assertIn(message_root_id, got)
        self.assertIn(reply_msg, got)
        self.assertEqual(mem.prefetched, [message_root_id])
        self.assertEqual(mem.get_calls, [])
        self.assertLessEqual(len(got), 10)

    def test_ttg_counts_foreign_root_against_prefetch_limit(self) -> None:
        got, channel, parent_msg, reply_msg, message_root_id, mem = (
            self._run_cross_root_ttg(2)
        )

        self.assertNotIn(channel, got)
        self.assertIn(parent_msg, got)
        self.assertIn(message_root_id, got)
        self.assertNotIn(reply_msg, got)
        self.assertEqual(len(got), 2)
        self.assertEqual(mem.prefetched, [message_root_id])
        self.assertEqual(mem.get_calls, [])
