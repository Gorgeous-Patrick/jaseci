"""Regression coverage for scope-sensitive validation memoization."""
import jaclang.sql as s;
import from unittest { TestCase }

test "SQL cache: immutable schemas are reused" {
    check = TestCase();
    a = s.select([s.named('n', s.int64(1))]);
    b = s.select([s.named('n', s.int64(2))]);
    union = s.union_all(a, b);
    assert a.ast.schema is a.ast.schema;
    assert union.ast.schema is union.ast.schema;
    with check.assertRaises(s.SqlError) {
        ast: any = a.ast;
        ast._schema_cache = s.Schema((s.FieldDef('wrong', s.DataType('text')), ));
    }
    s.compile_sql(union);
}

test "SQL cache: expression visibility is scoped" {
    check = TestCase();
    key = s.field('n', s.int64_type());
    source = s.table('numbers', [key]);
    expr = source.col(key).ast;
    validator = s.QueryValidator();
    validator.expr(expr, [source], [source], []);
    assert len(validator.expression_cache) == 1;
    validator.expr(expr, [source], [source], []);
    assert len(validator.expression_cache) == 1;
    with check.assertRaises(s.SqlError) {
        validator.expr(expr, [], [], []);
    }
    assert len(validator.expression_cache) == 1;
}

test "SQL cache: correlated query needs its outer scope" {
    check = TestCase();
    key = s.field('n', s.int64_type());
    source = s.table('numbers', [key]);
    query = s.select([s.named('n', source.col(key))]);
    validator = s.QueryValidator();
    validator.query(query.ast, [source], []);
    validator.query(query.ast, [source], []);
    assert len(validator.query_cache) == 1;
    with check.assertRaises(s.SqlError) {
        validator.query(query.ast, [], []);
    }
}

test "SQL cache: CTE visibility is scoped" {
    check = TestCase();
    key = s.field('n', s.int64_type());
    reference = s.cte(s.select([s.named('n', s.int64(1))]));
    query = s.select([s.named('n', reference.col(key))], source=reference);
    validator = s.QueryValidator();
    validator.query(query.ast, [], [reference]);
    with check.assertRaises(s.SqlError) {
        validator.query(query.ast, [], []);
    }
}

test "SQL cache: analyze clears previous results" {
    query = s.select([s.named('n', s.int64(1))]);
    validator = s.QueryValidator();
    validator.analyze(query);
    old_keys = set(validator.query_cache);
    next_query = s.select([s.named('n', s.int64(2))]);
    validator.analyze(next_query);
    assert not (old_keys & set(validator.query_cache));
}


test "SQL cache: replay free CTE dependencies without rescanning structure" {
    import from unittest.mock { patch }
    c = s.cte(s.select([s.named('n', s.int64(1))]));
    body = s.select(s.project_all(c), source=c);
    local = s.with_ctes(body, [c]);
    scan = s.QueryGraph();
    with patch.object(scan, 'scan_query', wraps=scan.scan_query) as scanner {
        scan.visit_query(local.ast);
        assert not scan.ctes;
        scans = scanner.call_count;
        scan.visit_query(body.ast);
        assert scanner.call_count == scans;
        assert len(scan.ctes) == 1 and scan.ctes[0] is c;
    }
}

test "SQL constructors: typed operations skip duplicate signature analysis" {
    import from unittest.mock { patch }
    integer = s.int64(1);
    small = s.int32(1);
    numeric = s.numeric(1);
    floating = s.param(s.float64_type(), 1.0);
    truth = s.boolean(True);
    text = s.text('x');
    optional = s.param(s.nullable(s.int64_type()), None);
    maybe_bool = s.param(s.nullable(s.bool_type()), None);
    source = s.table('people', [s.field('n', s.int64_type())]);
    with patch.object(
        s, 'same_type', side_effect=AssertionError('constructor repeated type analysis')
    ), patch.object(
        s,
        '_aggregate_type',
        side_effect=AssertionError('constructor repeated aggregate analysis')
    ) {
        expression = s.add(integer, s.sub(integer, integer));
        s.eq_nullable(optional, optional);
        s.coalesce(optional, integer);
        s.is_null(optional);
        s.and_([truth, s.not_(truth)]);
        s.or_([truth]);
        s.and_nullable([truth, maybe_bool]);
        s.or_nullable([truth, maybe_bool]);
        s.not_nullable(maybe_bool);
        s.sum_(floating);
        s.sum_int32(small);
        s.sum_int64(integer);
        s.sum_numeric(numeric);
        s.bool_and(truth);
        s.bool_or(maybe_bool);
        s.string_agg(text, text);
        s.inner_join(source, truth);
        query = s.select([s.named('n', expression)], where=truth);
    }
    s.compile_sql(query);
}
