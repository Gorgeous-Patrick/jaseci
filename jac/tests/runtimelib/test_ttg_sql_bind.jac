"""Repeated TTG requests bind values without recompiling query structure."""
import jaclang.sql as sql;
import from uuid { UUID }
import from unittest.mock { patch }
import from jaclang.runtime.ttg_sql {
    compile_specialized,
    compile_layered,
    _specialized_plan,
    _layered_plan
}

glob q: any = sql;

def _specs -> list[dict] {
    return [
        {
            'idx': 0,
            'from_type': 'Profile',
            'chain': [('Follow', 'Profile', 2)],
            'is_visit': True
        }
    ];
}

test "TTG bind: specialized request values reuse compiled SQL" {
    cache: any = _specialized_plan;
    cache.cache_clear();
    a = UUID(int=1);
    b = UUID(int=2);
    with patch.object(q, 'compile_sql', wraps=q.compile_sql) as compiler {
        first = compile_specialized(_specs(), [a], 3, 2);
        second = compile_specialized(_specs(), [b], 12, 9);
        assert compiler.call_count == 1;
        assert first.sql is second.sql;
        assert first.params['origin_ids'] == (a, );
        assert second.params['origin_ids'] == (b, );
        assert first.params['limit'] == 3;
        assert second.params['limit'] == 12;
        assert second.params['max_depth'] == 9;
        assert not first.slots and not second.slots;
    }
    assert cache.cache_info().maxsize == 128;
}

test "TTG bind: layered frontier and seen values reuse compiled SQL" {
    cache: any = _layered_plan;
    cache.cache_clear();
    a = UUID(int=1);
    b = UUID(int=2);
    with patch.object(q, 'compile_sql', wraps=q.compile_sql) as compiler {
        first = compile_layered(_specs(), [a], [], 12, False);
        second = compile_layered(_specs(), [b], [a], 3, False);
        assert compiler.call_count == 1;
        assert first.sql is second.sql;
        assert first.params['seen_empty'] == True;
        assert second.params['seen_empty'] == False;
        assert second.params['seen_ids'] == (a, );
        assert second.params['frontier_ids'] == (b, );
        assert second.params['limit'] == 3;
        assert first.params['seen_ids'] == ();
    }
    assert cache.cache_info().maxsize == 128;
}

test "TTG bind: structure flags and mutated specs select distinct plans" {
    specialized: any = _specialized_plan;
    layered: any = _layered_plan;
    specialized.cache_clear();
    layered.cache_clear();
    specs = _specs();
    with patch.object(q, 'compile_sql', wraps=q.compile_sql) as compiler {
        compile_specialized(specs, [], 1, 1, False, True);
        compile_specialized(specs, [], 1, 1, True, True);
        compile_specialized(specs, [], 1, 1, False, False);
        compile_layered(specs, [], [], 1, False, False);
        compile_layered(specs, [], [], 1, True, False);
        compile_layered(specs, [], [], 1, False, True);
        assert compiler.call_count == 6;
        specs[0]['chain'] = [('Follow', 'Profile', 1)];
        compile_specialized(specs, [], 1, 1);
        compile_layered(specs, [], [], 1, False);
        assert compiler.call_count == 8;
        compile_specialized(_specs(), [], 9, 9);
        compile_layered(_specs(), [], [], 9, False);
        assert compiler.call_count == 8;
    }
}


test "TTG columns: local field descriptors and column references are reused" {
    import from jaclang.runtime.ttg_sql { _BuildColumns }
    a = q.select([q.named('n', q.int64(1)), q.named('m', q.int64(2))]);
    b = q.select([q.named('n', q.int64(3)), q.named('m', q.int64(4))]);
    source = q.union_all(a, b).as_source();
    previous_keys = set(source.__dict__);
    cols = _BuildColumns();
    with patch.object(
        q.Schema, 'find', side_effect=AssertionError('field lookup repeated')
    ), patch.object(
        q, '_set_schema', side_effect=AssertionError('schema derivation repeated')
    ) {
        n = cols.col(source, 'n');
        assert cols.col(source, 'n') is n;
        assert cols.pick(source, ['n', 'm'])[0][1] is n;
        assert cols.names(source) == ['n', 'm'];
    }
    assert set(source.__dict__) == previous_keys;
}


test "TTG columns: constructor contexts do not retain stale field types" {
    import from jaclang.runtime.ttg_sql { _BuildColumns }
    query = q.select([q.named('n', q.int64(1))]);
    source = query.as_source();
    first = _BuildColumns();
    old_column = first.col(source, 'n');
    replacement = q.select([q.named('n', q.text('changed'))]);
    query.ast.projections = replacement.ast.projections;
    second = _BuildColumns();
    new_column = second.col(source, 'n');
    assert old_column.ast.dtype.name == 'bigint';
    assert new_column.ast.dtype.name == 'text';
    assert old_column is not new_column;
}


test "TTG columns: source bindings keep distinct column identities" {
    import from jaclang.runtime.ttg_sql { _BuildColumns }
    source = q.table('people', [q.field('id', q.int64_type())]);
    other = source.ref();
    cols = _BuildColumns();
    a = cols.col(source, 'id');
    b = cols.col(other, 'id');
    assert a is not b;
    assert a.ast.source is source;
    assert b.ast.source is other;
}
