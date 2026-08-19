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

    def get(self, uid: UUID) -> object:
        return self.anchors[uid]

    def prefetch(self, ids: Iterable[UUID]) -> None:
        self.prefetched.extend(ids)


class TTGCrossRootTest(unittest.TestCase):
    def test_ttg_bfs_uses_foreign_root_index_for_next_visit(self) -> None:
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
                object(), channel, channel_idx, mem, 10
            )
        finally:
            JacTTGGenerator._extract_visits_from_ast = orig

        self.assertIn(channel, got)
        self.assertIn(parent_msg, got)
        self.assertIn(reply_msg, got)
