"""Full native visit pairs share the Session mutation invalidation boundary."""
import from tempfile { TemporaryDirectory }
import from unittest.mock { patch }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.runtime.graph_query { GraphQuery, QHop }
import from jaclang.data.query_planner { resolve_ttg_path, resolve_query_prefix }
import from .fixtures.ttg_prefetch_helpers {
    seed_fetch_graph,
    open_fetch_context,
    fetch_origin
}
import from .fixtures.ttg_prefetch_walkers { FetchB, FetchLink }

test "TTG path lookup seeds native query cache and a topology mutation invalidates it" {
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            try {
                origin = fetch_origin(ctx, ids['start']);
                query = GraphQuery(
                    origin, hops=[QHop(dir=2, `edge=FetchLink, nd=FetchB)]
                ).`visit();
                store: any = ctx.mem.store;
                with patch.object(store, 'rows', wraps=store.rows) as rows {
                    resolved = resolve_ttg_path(ctx.mem, query, ids['start'], 200);
                    assert resolved is not None;
                    assert len(resolved) == 1;
                    initial_calls = rows.call_count;
                    assert initial_calls == 1;
                    actual = resolve_query_prefix(ctx.mem, query, 1);
                    assert set(actual) == ids['b'];
                    assert rows.call_count == initial_calls , str(rows.call_count);
                    again = resolve_ttg_path(ctx.mem, query, ids['start'], 200);
                    assert again == resolved;
                    assert rows.call_count == initial_calls;
                    other = FetchB();
                    origin +>:FetchLink:+> other;
                    changed = resolve_query_prefix(ctx.mem, query, 1);
                    assert set(changed) == ids['b'] | {other.__jac__.id};
                    assert rows.call_count > initial_calls;
                }
            } finally {
                ctx.close();
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}
