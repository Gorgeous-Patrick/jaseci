"""Tests for the transient GTI used by TTG planning."""

import os;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from uuid { UUID }
import from jaclang.runtime.archetype { EdgeAnchor, NodeAnchor, Root }
import from jaclang.runtime.context { ExecutionContext }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.runtime.topology_index { TopologyIndex }
import from jaclang.runtime.ttg {
    JacTTGGenerator,
    _ttg_render_specialized_set_based_sql,
    _resolve_sql_visit_bfs_layered_budgeted
}

import from jaclang.runtime.ttg_sql { compile_specialized, compile_layered }
import from .fixtures.ttg_sql_legacy {
    _ttg_render_specialized_set_based_sql as legacy_specialized,
    layered_sql as legacy_layered
}
import from unittest.mock { patch }


node GTIProfile {
    has name: str = "";
}

node GTISpecialProfile(GTIProfile) {}

node GTITweet {
    has text: str = "";

    def root_profiles -> list[GTIProfile] {
        return [root-->[?:GTIProfile]];
    }

    def local_origin_profiles -> list[GTIProfile] {
        msg = self;
        return [msg-->[?:GTIProfile]];
    }
}

edge GTIFollow {}

edge GTIStrongFollow(GTIFollow) {}

edge GTIPost {}


walker GTITraverse {
    can step_profile with GTIProfile entry {
        visit [-->[?:GTIProfile]];
        visit [-->[?:GTITweet]];
    }
}


walker GTIMultiHopTraverse {
    can step_profile with GTIProfile entry {
        visit [->:GTIFollow:->[?:GTIProfile]->:GTIPost:->[?:GTITweet]];
    }
}


walker GTIPartialLayerTraverse {
    can step_profile with GTIProfile entry {
        visit [->:GTIFollow:->[?:GTIProfile]];
        visit [->:GTIPost:->[?:GTITweet]];
    }
}


walker GTIRootSourceMethodTraverse {
    can step_profile with GTIProfile entry {
        visit [->:GTIPost:->[?:GTITweet]];
    }

    can step_tweet with GTITweet entry {
        here.root_profiles();
        here.local_origin_profiles();
    }
}


def _as_any(v: any) -> any {
    return v;
}


def _ctx(td: str) -> ExecutionContext {
    return ExecutionContext(
        base_path_dir=td, full_target_path=str(Path(td) / "gti_app.jac")
    );
}


def _root(ctx: ExecutionContext) -> NodeAnchor {
    ranch = Root().__jac__;
    ranch.ensure_id();
    ranch.persistent = True;
    setattr(ranch, "root", ranch.id);
    ctx.mem.put(ranch);
    return ranch;
}


def _owned_node(ctx: ExecutionContext, owner: NodeAnchor, arch: any) -> NodeAnchor {
    anch = arch.__jac__;
    anch.ensure_id();
    anch.persistent = True;
    setattr(anch, "root", owner.id);
    ctx.mem.put(anch);
    return anch;
}


def _connect(
    ctx: ExecutionContext, source: NodeAnchor, target: NodeAnchor, arch: any
) -> EdgeAnchor {
    eanch = EdgeAnchor(
        archetype=arch, source=source, target=target, is_undirected=False
    );
    eanch.ensure_id();
    eanch.persistent = True;
    eanch.`root = source.`root;
    source.edges.append(eanch);
    target.edges.append(eanch);
    ctx.mem.put(eanch);
    return eanch;
}


def _seed_cross_root(ctx: ExecutionContext) -> tuple[UUID, UUID, UUID, UUID, UUID] {
    alice_root = _root(ctx);
    bob_root = _root(ctx);
    alice = _owned_node(ctx, alice_root, GTIProfile(name="alice"));
    bob = _owned_node(ctx, bob_root, GTISpecialProfile(name="bob"));
    tweet = _owned_node(ctx, bob_root, GTITweet(text="hi"));
    _connect(ctx, alice, bob, _as_any(GTIStrongFollow()));
    _connect(ctx, bob, tweet, _as_any(GTIPost()));
    return (
        alice_root.ensure_id(),
        bob_root.ensure_id(),
        alice.ensure_id(),
        bob.ensure_id(),
        tweet.ensure_id()
    );
}


def _seed_partial_layer(ctx: ExecutionContext) -> tuple[UUID, list[UUID], list[UUID]] {
    ranch = _root(ctx);
    alice = _owned_node(ctx, ranch, GTIProfile(name="alice"));
    bob_ids: list[UUID] = [];
    tweet_ids: list[UUID] = [];
    for bob_idx in range(3) {
        bob = _owned_node(ctx, ranch, GTIProfile(name=f"bob-{bob_idx}"));
        bob_ids.append(bob.ensure_id());
        _connect(ctx, alice, bob, _as_any(GTIFollow()));
        for tweet_idx in range(5) {
            tweet = _owned_node(
                ctx, ranch, GTITweet(text=f"tweet-{bob_idx}-{tweet_idx}")
            );
            tweet_ids.append(tweet.ensure_id());
            _connect(ctx, bob, tweet, _as_any(GTIPost()));
        }
    }
    return (alice.ensure_id(), bob_ids, tweet_ids);
}


def _seed_overlap_budget(
    ctx: ExecutionContext
) -> tuple[UUID, list[UUID], list[UUID], list[UUID]] {
    ranch = _root(ctx);
    alice = _owned_node(ctx, ranch, GTIProfile(name="alice"));
    bob_ids: list[UUID] = [];
    shared_ids: list[UUID] = [];
    tweet_ids: list[UUID] = [];
    for shared_idx in range(5) {
        shared = _owned_node(ctx, ranch, GTIProfile(name=f"shared-{shared_idx}"));
        shared_ids.append(shared.ensure_id());
    }
    for bob_idx in range(3) {
        bob = _owned_node(ctx, ranch, GTIProfile(name=f"bob-{bob_idx}"));
        bob_ids.append(bob.ensure_id());
        _connect(ctx, alice, bob, _as_any(GTIFollow()));
        tweet = _owned_node(ctx, ranch, GTITweet(text=f"tweet-{bob_idx}"));
        tweet_ids.append(tweet.ensure_id());
        _connect(ctx, bob, tweet, _as_any(GTIPost()));
        for shared_id in shared_ids {
            shared_anchor = ctx.mem.get(shared_id);
            assert isinstance(shared_anchor, NodeAnchor);
            _connect(ctx, bob, _as_any(shared_anchor), _as_any(GTIFollow()));
        }
    }
    return (alice.ensure_id(), bob_ids, shared_ids, tweet_ids);
}


test "topology index resolves chains with type ancestry" {
    root_id = UUID("00000000-0000-0000-0000-000000000001");
    alice_id = UUID("00000000-0000-0000-0000-000000000101");
    bob_id = UUID("00000000-0000-0000-0000-000000000102");
    tweet_id = UUID("00000000-0000-0000-0000-000000000103");
    follow_id = UUID("00000000-0000-0000-0000-000000000201");
    post_id = UUID("00000000-0000-0000-0000-000000000202");

    idx = TopologyIndex();
    idx.add_node(alice_id, "GTIProfile", ["GTIProfile"], root_id);
    idx.add_node(
        bob_id, "GTISpecialProfile", ["GTISpecialProfile", "GTIProfile"], root_id
    );
    idx.add_node(tweet_id, "GTITweet", ["GTITweet"], root_id);
    idx.add_edge(
        follow_id, alice_id, bob_id, "GTIStrongFollow", ["GTIStrongFollow", "GTIFollow"]
    );
    idx.add_edge(post_id, bob_id, tweet_id, "GTIPost", ["GTIPost"]);

    assert idx.resolve_chain(
        [alice_id], [("GTIFollow", "GTIProfile", 2), ("GTIPost", "GTITweet", 2)], 10
    )
        == [tweet_id];
}


test "builder warms owner topology from seed nodes across roots" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, UUID, UUID, UUID, UUID];
        try {
            ids = _seed_cross_root(ctx1);
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            (alice_root_id, bob_root_id, alice_id, bob_id, tweet_id) = ids;
            idx = ctx2.mem.warm_topology_for_nodes([alice_id]);
            assert isinstance(idx, TopologyIndex);
            assert idx.has_root(alice_root_id);
            assert not idx.has_root(bob_root_id);
            assert idx.owner_root_for(bob_id) == bob_root_id;
            assert idx.resolve_chain([alice_id], [("GTIFollow", "GTIProfile", 2)], 10)
                == [bob_id];
            assert idx.resolve_chain(
                [alice_id],
                [("GTIFollow", "GTIProfile", 2), ("GTIPost", "GTITweet", 2)],
                10
            )
                == [];

            idx = ctx2.mem.warm_topology_for_nodes([bob_id]);
            assert idx.has_root(bob_root_id);
            assert idx.resolve_chain(
                [alice_id],
                [("GTIFollow", "GTIProfile", 2), ("GTIPost", "GTITweet", 2)],
                10
            )
                == [tweet_id];
        } finally {
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "filtered hop warm indexes only matching frontier adjacency" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, UUID, UUID, UUID, UUID];
        try {
            ids = _seed_cross_root(ctx1);
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            (alice_root_id, bob_root_id, alice_id, bob_id, tweet_id) = ids;
            idx = ctx2.mem.warm_topology_for_hop([alice_id], "GTIPost", "GTITweet", 2);
            assert isinstance(idx, TopologyIndex);
            assert not idx.has_root(alice_root_id);
            assert idx.node_type(alice_id) == "GTIProfile";
            assert idx.resolve_chain([alice_id], [("GTIFollow", "GTIProfile", 2)], 10)
                == [];

            idx = ctx2.mem.warm_topology_for_hop(
                [alice_id], "GTIFollow", "GTIProfile", 2
            );
            assert not idx.has_root(alice_root_id);
            assert not idx.has_root(bob_root_id);
            assert idx.owner_root_for(bob_id) == bob_root_id;
            assert idx.resolve_chain([alice_id], [("GTIFollow", "GTIProfile", 2)], 10)
                == [bob_id];
            assert idx.resolve_chain(
                [alice_id],
                [("GTIFollow", "GTIProfile", 2), ("GTIPost", "GTITweet", 2)],
                10
            )
                == [];

            idx = ctx2.mem.warm_topology_for_hop([bob_id], "GTIPost", "GTITweet", 2);
            assert idx.resolve_chain(
                [alice_id],
                [("GTIFollow", "GTIProfile", 2), ("GTIPost", "GTITweet", 2)],
                10
            )
                == [tweet_id];
        } finally {
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "TTG dedups overlapping candidates before applying layer budget" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        old_owner_roots = os.environ.get("JAC_TTG_PREFETCH_OWNER_ROOTS");
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, list[UUID], list[UUID], list[UUID]];
        try {
            ids = _seed_overlap_budget(ctx1);
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            os.environ.pop("JAC_TTG_PREFETCH_OWNER_ROOTS", None);
            (alice_id, bob_ids, shared_ids, tweet_ids) = ids;
            alice = ctx2.mem.get(alice_id);
            assert isinstance(alice, NodeAnchor);
            plan = JacTTGGenerator.get_ttg_prefetch_list(
                GTIPartialLayerTraverse(), alice, ctx2.mem, max_length=12
            );
            assert len(plan) == 12 , plan;
            assert alice_id in plan , plan;
            for bob_id in bob_ids {
                assert bob_id in plan , plan;
            }
            for shared_id in shared_ids {
                assert shared_id in plan , plan;
            }
            for tweet_id in tweet_ids {
                assert tweet_id in plan , plan;
            }
        } finally {
            if old_owner_roots is None {
                os.environ.pop("JAC_TTG_PREFETCH_OWNER_ROOTS", None);
            } else {
                os.environ["JAC_TTG_PREFETCH_OWNER_ROOTS"] = old_owner_roots;
            }
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "TTG partial layer marks only complete expansion groups loaded" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, list[UUID], list[UUID]];
        try {
            ids = _seed_partial_layer(ctx1);
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            (alice_id, bob_ids, tweet_ids) = ids;
            alice = ctx2.mem.get(alice_id);
            assert isinstance(alice, NodeAnchor);
            plan = JacTTGGenerator.get_ttg_prefetch_list(
                GTIPartialLayerTraverse(), alice, ctx2.mem, max_length=10
            );
            prefetched_tweets = [
                uid
                for uid in tweet_ids
                if uid in plan
            ];
            assert len(prefetched_tweets) > 0 , plan;
            idx = ctx2.mem.__topology_index__;
            assert isinstance(idx, TopologyIndex);
            loaded_post_hops = 0;
            for bob_id in bob_ids {
                if idx.has_hop(bob_id, "GTIPost", "GTITweet", 2) {
                    loaded_post_hops += 1;
                }
            }
            assert loaded_post_hops > 0 , loaded_post_hops;
            assert loaded_post_hops < len(bob_ids) , loaded_post_hops;
        } finally {
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "TTG uses warmed topology to continue across owner roots" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        old_owner_roots = os.environ.get("JAC_TTG_PREFETCH_OWNER_ROOTS");
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, UUID, UUID, UUID, UUID];
        try {
            ids = _seed_cross_root(ctx1);
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            os.environ.pop("JAC_TTG_PREFETCH_OWNER_ROOTS", None);
            (alice_root_id, bob_root_id, alice_id, bob_id, tweet_id) = ids;
            alice = ctx2.mem.get(alice_id);
            assert isinstance(alice, NodeAnchor);
            plan = JacTTGGenerator.get_ttg_prefetch_list(
                GTITraverse(), alice, ctx2.mem, max_length=10
            );
            assert bob_id in plan , plan;
            assert tweet_id in plan , plan;
            assert alice_root_id not in plan , plan;
            assert bob_root_id not in plan , plan;
            assert len(plan) <= 10 , plan;
            idx = ctx2.mem.__topology_index__;
            assert isinstance(idx, TopologyIndex);
            assert idx.owner_root_for(alice_id) == alice_root_id;
            assert idx.owner_root_for(bob_id) == bob_root_id;
            assert idx.owner_root_for(tweet_id) == bob_root_id;

            limited = JacTTGGenerator.get_ttg_prefetch_list(
                GTITraverse(), alice, ctx2.mem, max_length=2
            );
            assert len(limited) == 2 , limited;
            assert alice_id in limited , limited;
            assert bob_id in limited , limited;
            assert alice_root_id not in limited , limited;
            assert bob_root_id not in limited , limited;
            assert tweet_id not in limited , limited;

            os.environ["JAC_TTG_PREFETCH_OWNER_ROOTS"] = "1";
            with_roots = JacTTGGenerator.get_ttg_prefetch_list(
                GTITraverse(), alice, ctx2.mem, max_length=10
            );
            assert alice_root_id in with_roots , with_roots;
            assert bob_root_id in with_roots , with_roots;
        } finally {
            if old_owner_roots is None {
                os.environ.pop("JAC_TTG_PREFETCH_OWNER_ROOTS", None);
            } else {
                os.environ["JAC_TTG_PREFETCH_OWNER_ROOTS"] = old_owner_roots;
            }
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "TTG specialized SQL lowers a multi-hop visit chain" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        old_owner_roots = os.environ.get("JAC_TTG_PREFETCH_OWNER_ROOTS");
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, UUID, UUID, UUID, UUID];
        try {
            ids = _seed_cross_root(ctx1);
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            os.environ.pop("JAC_TTG_PREFETCH_OWNER_ROOTS", None);
            (alice_root_id, bob_root_id, alice_id, bob_id, tweet_id) = ids;
            alice = ctx2.mem.get(alice_id);
            assert isinstance(alice, NodeAnchor);
            plan = JacTTGGenerator.get_ttg_prefetch_list(
                GTIMultiHopTraverse(), alice, ctx2.mem, max_length=10
            );
            assert alice_id in plan , plan;
            assert tweet_id in plan , plan;
            assert alice_root_id not in plan , plan;
            assert bob_root_id not in plan , plan;
            assert bob_id not in plan , plan;
            idx = ctx2.mem.__topology_index__;
            assert isinstance(idx, TopologyIndex);
            assert idx.resolve_chain(
                [alice_id],
                [("GTIFollow", "GTIProfile", 2), ("GTIPost", "GTITweet", 2)],
                10
            )
                == [tweet_id];
            assert idx.owner_root_for(tweet_id) == bob_root_id;
        } finally {
            if old_owner_roots is None {
                os.environ.pop("JAC_TTG_PREFETCH_OWNER_ROOTS", None);
            } else {
                os.environ["JAC_TTG_PREFETCH_OWNER_ROOTS"] = old_owner_roots;
            }
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "TTG extractor skips explicit non-current edge-ref origins" {
    with TemporaryDirectory() as td {
        old = JacRuntime.exec_ctx;
        ctx1 = _ctx(td);
        JacRuntime.exec_ctx = ctx1;
        ids: tuple[UUID, UUID, UUID, UUID, UUID];
        try {
            alice_root = _root(ctx1);
            bob_root = _root(ctx1);
            alice = _owned_node(ctx1, alice_root, GTIProfile(name="alice"));
            bob = _owned_node(ctx1, bob_root, GTIProfile(name="bob"));
            tweet = _owned_node(ctx1, alice_root, GTITweet(text="hi"));
            _connect(ctx1, alice_root, alice, _as_any(GTIPost()));
            _connect(ctx1, bob_root, bob, _as_any(GTIPost()));
            _connect(ctx1, alice, tweet, _as_any(GTIPost()));
            _connect(ctx1, tweet, bob, _as_any(GTIFollow()));
            ids = (
                alice_root.ensure_id(),
                bob_root.ensure_id(),
                alice.ensure_id(),
                bob.ensure_id(),
                tweet.ensure_id()
            );
            ctx1.mem.commit();
        } finally {
            JacRuntime.exec_ctx = old;
            ctx1.close();
        }
        ctx2 = _ctx(td);
        JacRuntime.exec_ctx = ctx2;
        try {
            (alice_root_id, bob_root_id, alice_id, bob_id, tweet_id) = ids;
            ctx2.set_user_root(str(alice_root_id));
            loaded = ctx2.mem.get(tweet_id);
            assert isinstance(loaded, NodeAnchor);
            plan = JacTTGGenerator.get_ttg_prefetch_list(
                GTIRootSourceMethodTraverse(), loaded, ctx2.mem, max_length=10
            );
            assert tweet_id in plan , plan;
            assert alice_id in plan , plan;
            assert alice_root_id in plan , plan;
            assert bob_id not in plan , plan;
            assert bob_root_id not in plan , plan;
        } finally {
            JacRuntime.exec_ctx = old;
            ctx2.close();
        }
    }
}


test "TTG complete-hop SQL optimization has env escape hatch" {
    specs = [
        {
            "idx": 0,
            "from_type": "GTIProfile",
            "chain": [("GTIFollow", "GTIProfile", 2)],
            "is_visit": True,
            "origin_name": ""
        }
    ];
    old = os.environ.get("JAC_TTG_OPT_COMPLETE_HOPS");
    try {
        os.environ.pop("JAC_TTG_OPT_COMPLETE_HOPS", None);
        sql = _ttg_render_specialized_set_based_sql(
            specs, {"origin_ids": [], "limit": 10, "max_depth": 10}
        );
        assert "BOOL_AND(" in sql;
        assert '"group_complete"' in sql;
        assert "IS NOT NULL" in sql;
        assert "MATERIALIZED" in sql;
        assert " AS boolean)" in sql;

        os.environ["JAC_TTG_OPT_COMPLETE_HOPS"] = "0";
        fallback_sql = _ttg_render_specialized_set_based_sql(
            specs, {"origin_ids": [], "limit": 10, "max_depth": 10}
        );
        assert "BOOL_AND(" not in fallback_sql;
        assert "NOT EXISTS (" in fallback_sql;
        assert '"group_complete"' in fallback_sql;
        assert "(NOT " in fallback_sql;
    } finally {
        if old is None {
            os.environ.pop("JAC_TTG_OPT_COMPLETE_HOPS", None);
        } else {
            os.environ["JAC_TTG_OPT_COMPLETE_HOPS"] = old;
        }
    }
}


test "TTG structured specialized query matches frozen SQL rows" {
    with TemporaryDirectory() as td {
        previous = JacRuntime.exec_ctx;
        ctx = _ctx(td);
        JacRuntime.exec_ctx = ctx;
        try {
            (alice, bobs, shared, tweets) = _seed_overlap_budget(ctx);
            ctx.mem.commit();
            specs = [
                {
                    'idx': 0,
                    'from_type': 'GTIProfile',
                    'chain': [('GTIFollow', 'GTIProfile', 2)],
                    'is_visit': True,
                    'origin_name': ''
                },
                {
                    'idx': 1,
                    'from_type': 'GTIProfile',
                    'chain': [('GTIPost', 'GTITweet', 2)],
                    'is_visit': True,
                    'origin_name': ''
                }
            ];
            store = ctx.mem.store;
            assert store is not None;
            params: dict[str, object] = {
                'origin_ids': [str(alice)],
                'limit': 12,
                'max_depth': 12
            };
            with patch.dict(
                os.environ,
                {'JAC_TTG_PREFETCH_OWNER_ROOTS': '0', 'JAC_TTG_OPT_COMPLETE_HOPS': '1'}
            ) {
                expected_sql = legacy_specialized(specs, params);
                expected = store.rows(expected_sql, params);
                compiled = compile_specialized(specs, [alice], 12, 12);
                actual = store.rows(compiled.sql, compiled.params);
                assert actual == expected , (actual, expected, compiled.sql);
            }
        } finally {
            JacRuntime.exec_ctx = previous;
            ctx.close();
        }
    }
}

def _sql_comparison_specs -> list[list[dict]] {
    result: list[list[dict]] = [];
    for direction in [1, 2, 3] {
        result.append(
            [
                {
                    'idx': 0,
                    'from_type': 'GTIProfile',
                    'chain': [('GTIFollow', 'GTIProfile', direction)],
                    'is_visit': True,
                    'origin_name': ''
                }
            ]
        );
    }
    result.append(
        [
            {
                'idx': 0,
                'from_type': 'GTIProfile',
                'chain': [('GTIFollow', 'GTIProfile', 2), ('GTIPost', 'GTITweet', 2)],
                'is_visit': True,
                'origin_name': ''
            }
        ]
    );
    result.append(
        [
            {
                'idx': 0,
                'from_type': 'GTIProfile',
                'chain': [('GTIFollow', 'GTIProfile', 2)],
                'is_visit': True,
                'origin_name': ''
            },
            {
                'idx': 1,
                'from_type': 'GTIProfile',
                'chain': [('GTIPost', 'GTITweet', 2)],
                'is_visit': False,
                'origin_name': ''
            }
        ]
    );
    result.append(
        [
            {
                'idx': 0,
                'from_type': None,
                'chain': [(None, None, 3)],
                'is_visit': True,
                'origin_name': ''
            }
        ]
    );
    return result;
}

test "TTG structured specialized matches legacy matrix" {
    with TemporaryDirectory() as td {
        previous = JacRuntime.exec_ctx;
        ctx = _ctx(td);
        JacRuntime.exec_ctx = ctx;
        try {
            (alice, bobs, shared, tweets) = _seed_overlap_budget(ctx);
            cross = _seed_cross_root(ctx);
            alice_anchor = ctx.mem.get(alice);
            bob_anchor = ctx.mem.get(bobs[0]);
            assert isinstance(alice_anchor, NodeAnchor);
            assert isinstance(bob_anchor, NodeAnchor);
            _connect(ctx, bob_anchor, alice_anchor, _as_any(GTIFollow()));
            ctx.mem.commit();
            store = ctx.mem.store;
            assert store is not None;
            origins = [alice, bobs[0], cross[2]];
            compared = 0;
            for specs in _sql_comparison_specs() {
                for limit in [0, 1, 5, 12] {
                    for include_roots in [False, True] {
                        for optimized in [False, True] {
                            params: dict[str, object] = {
                                'origin_ids': [str(uid) for uid in origins],
                                'limit': limit,
                                'max_depth': max(1, limit)
                            };
                            with patch.dict(
                                os.environ,
                                {
                                    'JAC_TTG_PREFETCH_OWNER_ROOTS': '1'
                                        if include_roots
                                        else '0',
                                    'JAC_TTG_OPT_COMPLETE_HOPS': '1'
                                        if optimized
                                        else '0'
                                }
                            ) {
                                expected = store.rows(
                                    legacy_specialized(specs, params), params
                                );
                                compiled = compile_specialized(
                                    specs,
                                    origins,
                                    limit,
                                    max(1, limit),
                                    include_roots,
                                    optimized
                                );
                                actual = store.rows(compiled.sql, compiled.params);
                                assert actual == expected , (
                                    specs,
                                    limit,
                                    include_roots,
                                    optimized,
                                    actual,
                                    expected
                                );
                                compared += 1;
                            }
                        }
                    }
                }
            }
            assert compared == 96 , compared;
        } finally {
            JacRuntime.exec_ctx = previous;
            ctx.close();
        }
    }
}

test "TTG structured layered query matches legacy matrix" {
    with TemporaryDirectory() as td {
        previous = JacRuntime.exec_ctx;
        ctx = _ctx(td);
        JacRuntime.exec_ctx = ctx;
        try {
            (alice, bobs, shared, tweets) = _seed_overlap_budget(ctx);
            ctx.mem.commit();
            store = ctx.mem.store;
            assert store is not None;
            origins = [alice, bobs[0]];
            compared = 0;
            for specs in _sql_comparison_specs() {
                for has_undirected in [False, True] {
                    for include_roots in [False, True] {
                        for seen in [[], [alice, bobs[1]]] {
                            with patch.dict(
                                os.environ,
                                {
                                    'JAC_TTG_PREFETCH_OWNER_ROOTS': '1'
                                        if include_roots
                                        else '0'
                                }
                            ) {
                                (sql, params) = legacy_layered(
                                    specs, 12, has_undirected
                                );
                                params['frontier_ids'] = [str(uid) for uid in origins];
                                params['seen_ids'] = [str(uid) for uid in seen]
                                    if seen
                                    else ['00000000-0000-0000-0000-000000000000'];
                                params['seen_count'] = len(seen);
                                params['limit'] = 12;
                                expected = store.rows(sql, params);
                                compiled = compile_layered(
                                    specs,
                                    origins,
                                    seen,
                                    12,
                                    has_undirected,
                                    include_roots
                                );
                                actual = store.rows(compiled.sql, compiled.params);
                                assert actual == expected , (
                                    specs,
                                    has_undirected,
                                    include_roots,
                                    seen,
                                    actual,
                                    expected
                                );
                                compared += 1;
                            }
                        }
                    }
                }
            }
            assert compared == 48 , compared;
        } finally {
            JacRuntime.exec_ctx = previous;
            ctx.close();
        }
    }
}


def _legacy_layered_plan(
    store: any, origins: list[UUID], specs: list[dict], limit: int, has_undirected: bool
) -> tuple[list[UUID], dict[UUID, str]] {
    (sql, base) = legacy_layered(specs, limit, has_undirected);
    prefetch: list[UUID] = [];
    seen: set[UUID] = set();
    expanded: set[UUID] = set();
    frontier = list(origins);
    depth = 0;
    types: dict[UUID, str] = {};
    while frontier and len(prefetch) < limit and depth < limit {
        params = dict(base);
        params['frontier_ids'] = [str(uid) for uid in frontier];
        params['seen_ids'] = [str(uid) for uid in seen]
            if seen
            else ['00000000-0000-0000-0000-000000000000'];
        params['seen_count'] = len(seen);
        params['limit'] = limit - len(prefetch);
        rows = store.rows(sql, params);
        next_frontier: list[UUID] = [];
        next_seen: set[UUID] = set();
        for row in rows {
            uid = UUID(str(row[1]));
            if uid in seen {
                continue;
            }
            if len(prefetch) >= limit {
                break;
            }
            seen.add(uid);
            prefetch.append(uid);
            types[uid] = str(row[2] or 'unknown');
            if bool(row[5]) and uid not in expanded and uid not in next_seen {
                next_seen.add(uid);
                next_frontier.append(uid);
            }
        }
        expanded.update(frontier);
        frontier = next_frontier;
        depth += 1;
    }
    return (prefetch, types);
}

test "TTG layered runtime matches legacy iteration with undirected edges" {
    with TemporaryDirectory() as td {
        previous = JacRuntime.exec_ctx;
        ctx = _ctx(td);
        JacRuntime.exec_ctx = ctx;
        try {
            (alice, bobs, shared, tweets) = _seed_overlap_budget(ctx);
            ctx.mem.commit();
            store = ctx.mem.store;
            assert store is not None;
            origins = [alice, bobs[0]];
            compared = 0;
            for undirected in [False, True] {
                if undirected {
                    alice_anchor = ctx.mem.get(alice);
                    assert isinstance(alice_anchor, NodeAnchor);
                    owner = _root(ctx);
                    outside = _owned_node(
                        ctx, owner, GTIProfile(name='undirected-only')
                    );
                    connection = _connect(
                        ctx, outside, alice_anchor, _as_any(GTIFollow())
                    );
                    connection.is_undirected = True;
                    ctx.mem.put(connection);
                    ctx.mem.commit();
                }
                for specs in _sql_comparison_specs() {
                    for limit in [3, 12, 30] {
                        for roots in [False, True] {
                            with patch.dict(
                                os.environ,
                                {'JAC_TTG_PREFETCH_OWNER_ROOTS': '1' if roots else '0'}
                            ) {
                                (expected, expected_types) = _legacy_layered_plan(
                                    store, origins, specs, limit, undirected
                                );
                                actual_types: dict[UUID, str] = {};
                                actual = _resolve_sql_visit_bfs_layered_budgeted(
                                    ctx.mem, origins, specs, limit, actual_types
                                );
                                assert actual == expected , (
                                    specs,
                                    limit,
                                    roots,
                                    undirected,
                                    actual,
                                    expected
                                );
                                assert actual_types == expected_types , (
                                    actual_types,
                                    expected_types
                                );
                                compared += 1;
                            }
                        }
                    }
                }
            }
            assert compared == 72 , compared;
        } finally {
            JacRuntime.exec_ctx = previous;
            ctx.close();
        }
    }
}
