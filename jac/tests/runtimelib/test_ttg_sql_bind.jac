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
