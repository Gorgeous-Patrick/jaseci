import from uuid { UUID }
import from functools { lru_cache }
import jaclang.sql as q;


def _c(source: any, name: str) -> any {
    definition = source.schema.find(name);
    return q.ScalarExpr(q.ColumnNode(dtype=definition.dtype, source=source, name=name));
}

def _pick(
    source: any, names: list[str], overrides: dict[str, any] = {}
) -> list[tuple[str, any]] {
    return [
        (name, overrides[name] if name in overrides else _c(source, name))
        for name in names
    ];
}

def _names(source: any) -> list[str] {
    return [f.name for f in source.schema.fields];
}

def _all(terms: list[any]) -> any {
    if not terms {
        return q.boolean(True);
    }
    return q.and_nullable(terms)
        if `any([t.ast.dtype.nullable for t in terms])
        else q.and_(terms);
}

def _either(terms: list[any]) -> any {
    if not terms {
        return q.boolean(False);
    }
    return q.or_nullable(terms)
        if `any([t.ast.dtype.nullable for t in terms])
        else q.or_(terms);
}

def _cmp(left: any, right: any, op: str = '=') -> any {
    return q.compare_nullable(left, right, op)
        if left.ast.dtype.nullable or right.ast.dtype.nullable
        else q._compare(left, right, op);
}

def _negated(term: any) -> any {
    return q.not_nullable(term) if term.ast.dtype.nullable else q.not_(term);
}

def _present(term: any) -> any {
    return q.is_not_null(term) if term.ast.dtype.nullable else q.boolean(True);
}

def _select(
    source: any,
    columns: list[tuple[str, any]],
    joins: list[any] = [],
    predicate: any = None,
    groups: list[any] = [],
    order: list[any] = [],
    distinct: bool = False,
    distinct_on: list[any] = []
) -> any {
    return q.select(
        [q.named(name, expr) for (name, expr) in columns],
        source=source,
        joins=joins,
        where=predicate,
        group_by=[g.ast for g in groups],
        order_by=order,
        distinct=distinct,
        distinct_on=[e.ast for e in distinct_on]
    );
}

def _anchors -> any {
    return q.table(
        'anchors',
        [
            q.field('id', q.uuid_type()),
            q.field('kind', q.text_type()),
            q.field('arch_type', q.text_type()),
            q.field('root_id', q.nullable(q.uuid_type())),
            q.field('src', q.nullable(q.uuid_type())),
            q.field('dst', q.nullable(q.uuid_type())),
            q.field('undirected', q.bool_type()),
            q.field('seq', q.nullable(q.int64_type()))
        ]
    );
}

def _types -> any {
    return q.table(
        'graph_types',
        [q.field('type_name', q.text_type()), q.field('ancestor', q.text_type())]
    );
}

def _expected(value: any) -> any {
    return q.param(q.nullable(q.text_type()), value);
}

def _match(arch_type: any, expected: any) -> any {
    ancestry = _types();
    inherited = _select(
        ancestry,
        [('one', q.int64(1))],
        predicate=_all(
            [
                _cmp(_c(ancestry, 'type_name'), arch_type),
                _cmp(_c(ancestry, 'ancestor'), expected)
            ]
        )
    );
    missing = q.is_null(expected) if expected.ast.dtype.nullable else q.boolean(False);
    return _either([missing, _cmp(arch_type, expected), q.exists(inherited)]);
}

def _owner(anchor: any) -> any {
    return q.case_nullable(
        [
            (
                _all(
                    [
                        _cmp(_c(anchor, 'kind'), q.text('NodeAnchor')),
                        _cmp(_c(anchor, 'arch_type'), q.text('Root'))
                    ]
                ),
                _c(anchor, 'id')
            )
        ],
        _c(anchor, 'root_id')
    );
}

def _union(queries: list[any], distinct: bool = False) -> any {
    if not queries {
        raise ValueError('TTG requires a nonempty query set');
    }
    result = queries[0];
    for query in queries[1:] {
        result = q.union(result, query) if distinct else q.union_all(result, query);
    }
    return result;
}

def _edge_branch(
    origin: any, source_name: str, target_name: str, edge_type: any, node_type: any
) -> any {
    edge_source = _anchors();
    target = _anchors();
    condition = _all(
        [
            _cmp(_c(target, 'id'), _c(edge_source, target_name)),
            _cmp(_c(target, 'kind'), q.text('NodeAnchor'))
        ]
    );
    return _select(
        edge_source,
        [
            ('edge_id', _c(edge_source, 'id')),
            ('edge_seq', q.coalesce(_c(edge_source, 'seq'), q.int64(0))),
            ('node_id', _c(target, 'id')),
            ('arch_type', _c(target, 'arch_type'))
        ],
        joins=[q.inner_join(target, condition)],
        predicate=_all(
            [
                _cmp(_c(edge_source, 'kind'), q.text('EdgeAnchor')),
                _cmp(_c(edge_source, source_name), origin),
                _present(_c(edge_source, target_name)),
                _match(_c(edge_source, 'arch_type'), edge_type),
                _match(_c(target, 'arch_type'), node_type)
            ]
        )
    );
}

def _hop(origin: any, prior: list[any], hop: any) -> any {
    direction = int(hop[2] or 2);
    branches: list[any] = [];
    edge_type = _expected(hop[0]);
    node_type = _expected(hop[1]);
    if direction in (2, 3) {
        branches.append(_edge_branch(origin, 'src', 'dst', edge_type, node_type));
    }
    if direction in (1, 3) {
        branches.append(_edge_branch(origin, 'dst', 'src', edge_type, node_type));
    }
    if not branches {
        raise ValueError(f'Unsupported TTG direction {direction}');
    }
    edges = _union(branches).as_source(lateral=True);
    conditions = [_cmp(_c(edges, 'node_id'), origin, '<>')]
        + [_cmp(_c(edges, 'node_id'), n, '<>') for n in prior];
    return _select(
        edges, _pick(edges, _names(edges)), predicate=_all(conditions)
    ).as_source(
        lateral=True
    );
}

def _hop_key(source: any) -> any {
    return q.concat(
        [
            q.lpad(
                q.cast(_c(source, 'edge_seq'), q.text_type()), q.int32(20), q.text('0')
            ),
            q.text(':'),
            q.cast(_c(source, 'edge_id'), q.text_type())
        ]
    );
}

def _frontier_spec(frontier: any, spec: dict) -> any {
    chain = spec.get('chain') or [];
    if not chain {
        raise ValueError('TTG requires a nonempty hop chain');
    }
    prior: list[any] = [];
    joins: list[any] = [];
    edge_ids: list[any] = [];
    keys: list[any] = [];
    origin = _c(frontier, 'node_id');
    final_source: any = None;
    for hop in chain {
        final_source = _hop(origin, prior, hop);
        joins.append(q.cross_join(final_source));
        origin = _c(final_source, 'node_id');
        prior.append(origin);
        edge_ids.append(_c(final_source, 'edge_id'));
        keys.append(_hop_key(final_source));
    }
    step_order = keys[0];
    for key in keys[1:] {
        step_order = q.text_concat(q.text_concat(step_order, q.text(':')), key);
    }
    return _select(
        frontier,
        [
            ('depth', q.add(_c(frontier, 'depth'), q.int64(1))),
            ('node_id', origin),
            ('arch_type', _c(final_source, 'arch_type')),
            ('parent_depth', _c(frontier, 'depth')),
            ('parent_bfs_ord', _c(frontier, 'bfs_ord')),
            ('parent_node_id', _c(frontier, 'node_id')),
            ('step_nodes', q.array(q.uuid_type(), prior)),
            ('step_edges', q.array(q.uuid_type(), edge_ids)),
            ('step_ord', step_order),
            ('is_frontier', q.boolean(bool(spec.get('is_visit')))),
            ('spec_idx', q.int64(int(spec['idx'])))
        ],
        joins=joins,
        predicate=_match(_c(frontier, 'arch_type'), _expected(spec.get('from_type')))
    );
}

def _group_keys(source: any) -> list[any] {
    return [
        _c(source, name) for name in ['parent_bfs_ord', 'spec_idx', 'parent_node_id']
    ];
}

def _partition_count(source: any) -> any {
    return q.over(q.count(), partition_by=[e.ast for e in _group_keys(source)]);
}

def _build_specialized(
    specs: list[dict], include_roots: bool = False, complete_optimization: bool = True
) -> q.CompiledSQL {
    bound_limit = q.slot('limit', q.int64_type());
    bound_depth = q.slot('max_depth', q.int64_type());
    numeric_limit = q.cast(bound_limit, q.numeric_type());
    walk_fields = [
        q.field('depth', q.int64_type()),
        q.field('bfs_ord', q.int64_type()),
        q.field('node_id', q.uuid_type()),
        q.field('arch_type', q.text_type()),
        q.field('parent_depth', q.nullable(q.int64_type())),
        q.field('parent_bfs_ord', q.nullable(q.int64_type())),
        q.field('parent_node_id', q.nullable(q.uuid_type())),
        q.field('step_nodes', q.array_type(q.uuid_type())),
        q.field('step_edges', q.array_type(q.uuid_type())),
        q.field('is_frontier', q.bool_type()),
        q.field('step_spec_idx', q.nullable(q.int64_type())),
        q.field('step_group_complete', q.nullable(q.bool_type()))
    ];
    walk = q.cte_ref(walk_fields);
    seed_id = q.field('id', q.uuid_type());
    seed_ord = q.field('ord', q.int64_type());
    seeds = q.unnest(
        q.slot('origin_ids', q.array_type(q.uuid_type())), seed_id, seed_ord
    );
    seed_nodes = _anchors();
    anchor = _select(
        seeds,
        [
            ('depth', q.int64(0)),
            ('bfs_ord', _c(seeds, 'ord')),
            ('node_id', _c(seeds, 'id')),
            ('arch_type', _c(seed_nodes, 'arch_type')),
            ('parent_depth', q.null(q.int64_type())),
            ('parent_bfs_ord', q.null(q.int64_type())),
            ('parent_node_id', q.null(q.uuid_type())),
            ('step_nodes', q.array(q.uuid_type(), [_c(seeds, 'id')])),
            ('step_edges', q.array(q.uuid_type(), [])),
            ('is_frontier', q.boolean(True)),
            ('step_spec_idx', q.null(q.int64_type())),
            ('step_group_complete', q.boolean(True))
        ],
        joins=[
            q.inner_join(
                seed_nodes,
                _all(
                    [
                        _cmp(_c(seed_nodes, 'id'), _c(seeds, 'id')),
                        _cmp(_c(seed_nodes, 'kind'), q.text('NodeAnchor'))
                    ]
                )
            )
        ]
    );
    frontier = q.cte(
        _select(
            walk,
            _pick(walk, _names(walk)),
            predicate=_all(
                [_c(walk, 'is_frontier'), _cmp(_c(walk, 'depth'), bound_depth, '<')]
            )
        ),
        materialized=True
    );
    frontier_nodes = q.cte(
        _select(frontier, _pick(frontier, ['node_id'])), materialized=True
    );
    raw = q.cte(_union([_frontier_spec(frontier, spec) for spec in specs]));
    already = q.exists(
        _select(
            frontier_nodes,
            [('one', q.int64(1))],
            predicate=_cmp(_c(frontier_nodes, 'node_id'), _c(raw, 'node_id'))
        )
    );
    annotated = q.cte(
        _select(
            raw,
            _pick(raw, _names(raw))
                + [
                    ('already_frontier', already),
                    ('raw_group_count', _partition_count(raw))
                ]
        )
    );
    unseen = q.cte(
        _select(
            annotated,
            _pick(annotated, _names(annotated)),
            predicate=q.not_(_c(annotated, 'already_frontier'))
        )
    );
    dedup = q.cte(
        _select(
            unseen,
            _pick(unseen, _names(unseen)),
            distinct_on=[_c(unseen, 'node_id')],
            order=[
                q.asc(_c(unseen, k))
                for k in [
                    'node_id',
                    'parent_bfs_ord',
                    'spec_idx',
                    'parent_node_id',
                    'step_ord'
                ]
            ]
        )
    );
    dedup_grouped = q.cte(
        _select(
            dedup,
            _pick(dedup, _names(dedup))
                + [('dedup_group_count', _partition_count(dedup))]
        )
    );
    group_order = [q.asc(e) for e in _group_keys(dedup_grouped)];
    grouped = q.cte(
        _select(
            dedup_grouped,
            _pick(dedup_grouped, _names(dedup_grouped))
                + [
                    ('group_ord', q.dense_rank(order_by=group_order)),
                    (
                        'group_row_rank',
                        q.row_number(
                            partition_by=[e.ast for e in _group_keys(dedup_grouped)],
                            order_by=[
                                q.asc(_c(dedup_grouped, 'step_ord')),
                                q.asc(_c(dedup_grouped, 'node_id'))
                            ]
                        )
                    ),
                    ('group_count', _partition_count(dedup_grouped))
                ]
        )
    );
    distinct_groups = q.cte(
        _select(grouped, _pick(grouped, ['group_ord', 'group_count']), distinct=True)
    );
    order_groups = [q.asc(_c(distinct_groups, 'group_ord'))];
    prior_count = q.coalesce(
        q.over(
            q.sum_int64(_c(distinct_groups, 'group_count')),
            order_by=order_groups,
            frame=q.rows_between(q.unbounded_preceding(), q.preceding(1))
        ),
        q.numeric(0)
    );
    cume_count = q.over(
        q.sum_int64(_c(distinct_groups, 'group_count')),
        order_by=order_groups,
        frame=q.rows_between(q.unbounded_preceding(), q.current_row())
    );
    budget = q.cte(
        _select(
            distinct_groups,
            _pick(distinct_groups, _names(distinct_groups))
                + [('group_prior_count', prior_count), ('group_cume_count', cume_count)]
        )
    );
    complete = _all(
        [
            _cmp(_c(budget, 'group_cume_count'), numeric_limit, '<='),
            _cmp(_c(grouped, 'dedup_group_count'), _c(grouped, 'raw_group_count'))
        ]
    );
    budgeted = q.cte(
        _select(
            grouped,
            _pick(grouped, _names(grouped))
                + _pick(budget, ['group_prior_count', 'group_cume_count'])
                + [('group_complete', complete)],
            joins=[
                q.inner_join(
                    budget, _cmp(_c(budget, 'group_ord'), _c(grouped, 'group_ord'))
                )
            ],
            predicate=_all(
                [
                    _cmp(_c(budget, 'group_prior_count'), numeric_limit, '<'),
                    _cmp(
                        q.cast(_c(grouped, 'group_row_rank'), q.numeric_type()),
                        q.numeric_sub(numeric_limit, _c(budget, 'group_prior_count')),
                        '<='
                    )
                ]
            )
        )
    );
    ranked = q.cte(
        _select(
            budgeted,
            _pick(budgeted, _names(budgeted))
                + [
                    (
                        'local_rank',
                        q.row_number(
                            order_by=[
                                q.asc(_c(budgeted, k))
                                for k in ['group_ord', 'group_row_rank', 'node_id']
                            ]
                        )
                    ),
                    ('layer_count', q.over(q.count()))
                ]
        )
    );
    step = _select(
        ranked,
        _pick(ranked, ['depth'], {})
            + [('bfs_ord', _c(ranked, 'local_rank'))]
            + _pick(
                ranked,
                [
                    'node_id',
                    'arch_type',
                    'parent_depth',
                    'parent_bfs_ord',
                    'parent_node_id',
                    'step_nodes',
                    'step_edges'
                ]
            )
            + [
                (
                    'is_frontier',
                    _all(
                        [
                            _c(ranked, 'is_frontier'),
                            _cmp(_c(ranked, 'layer_count'), bound_limit, '<')
                        ]
                    )
                ),
                ('step_spec_idx', _c(ranked, 'spec_idx')),
                ('step_group_complete', _c(ranked, 'group_complete'))
            ]
    );
    local = [
        frontier,
        frontier_nodes,
        raw,
        annotated,
        unseen,
        dedup,
        dedup_grouped,
        grouped,
        distinct_groups,
        budget,
        budgeted,
        ranked
    ];
    q.define_cte(walk, q.union_all(anchor, q.with_ctes(step, local)), recursive=True);
    anchor_source = _anchors();
    candidate = q.cte(
        _select(
            walk,
            _pick(walk, ['depth', 'bfs_ord'])
                + [('target_id', _c(walk, 'node_id'))]
                + _pick(
                    walk,
                    [
                        'parent_depth',
                        'parent_bfs_ord',
                        'parent_node_id',
                        'step_nodes',
                        'step_edges',
                        'is_frontier'
                    ]
                )
                + [
                    ('spec_idx', _c(walk, 'step_spec_idx')),
                    ('group_complete', _c(walk, 'step_group_complete')),
                    ('owner_root', _owner(anchor_source))
                ],
            joins=[
                q.inner_join(
                    anchor_source,
                    _all(
                        [
                            _cmp(_c(anchor_source, 'id'), _c(walk, 'node_id')),
                            _cmp(_c(anchor_source, 'kind'), q.text('NodeAnchor'))
                        ]
                    )
                )
            ]
        )
    );
    path_names = [
        'depth',
        'bfs_ord',
        'path_node_id',
        'parent_depth',
        'parent_bfs_ord',
        'parent_node_id',
        'step_nodes',
        'step_edges',
        'spec_idx'
    ];
    path_columns = _pick(candidate, ['depth', 'bfs_ord'])
        + [('path_node_id', _c(candidate, 'target_id'))]
        + _pick(
            candidate,
            [
                'parent_depth',
                'parent_bfs_ord',
                'parent_node_id',
                'step_nodes',
                'step_edges',
                'spec_idx'
            ]
        );
    node_additions = _select(
        candidate,
        path_columns
            + [
                ('sub_ord', q.int64(0)),
                ('id', _c(candidate, 'target_id')),
                ('is_frontier', _c(candidate, 'is_frontier'))
            ]
    );
    owner_additions = _select(
        candidate,
        path_columns
            + [
                ('sub_ord', q.int64(1)),
                ('id', _c(candidate, 'owner_root')),
                ('is_frontier', q.boolean(False))
            ],
        predicate=_all(
            [
                _present(_c(candidate, 'owner_root')),
                q.boolean(include_roots),
                _cmp(_c(candidate, 'owner_root'), _c(candidate, 'target_id'), '<>')
            ]
        )
    );
    additions = q.cte(q.union_all(node_additions, owner_additions));
    flags = q.cte(
        _select(
            additions,
            [
                ('id', _c(additions, 'id')),
                ('is_frontier', q.bool_or(_c(additions, 'is_frontier')))
            ],
            predicate=_present(_c(additions, 'id')),
            groups=[_c(additions, 'id')]
        )
    );
    dedup_additions = q.cte(
        _select(
            additions,
            _pick(additions, ['id'] + path_names + ['sub_ord'])
                + [('is_frontier', _c(flags, 'is_frontier'))],
            joins=[q.inner_join(flags, _cmp(_c(flags, 'id'), _c(additions, 'id')))],
            predicate=_present(_c(additions, 'id')),
            distinct_on=[_c(additions, 'id')],
            order=[
                q.asc(_c(additions, k)) for k in ['id', 'depth', 'bfs_ord', 'sub_ord']
            ]
        )
    );
    plan_fields = ['id'] + path_names + ['is_frontier'];
    ordered_plan = q.cte(
        _select(
            dedup_additions,
            _pick(dedup_additions, plan_fields)
                + [
                    (
                        'ord',
                        q.row_number(
                            order_by=[
                                q.asc(_c(dedup_additions, k))
                                for k in ['depth', 'bfs_ord', 'sub_ord', 'id']
                            ]
                        )
                    )
                ]
        )
    );
    prefetch = q.cte(
        _select(
            ordered_plan,
            _pick(ordered_plan, plan_fields + ['ord']),
            predicate=_cmp(_c(ordered_plan, 'ord'), bound_limit, '<=')
        )
    );
    stats = q.cte(q.aggregate([q.named('total', q.count())], source=ordered_plan));
    chosen_names = [
        'depth',
        'bfs_ord',
        'node_id',
        'parent_depth',
        'parent_bfs_ord',
        'parent_node_id',
        'step_nodes',
        'step_edges',
        'spec_idx'
    ];
    selected = q.cte(
        q.union_all(
            _select(
                prefetch,
                _pick(prefetch, chosen_names, {'node_id': _c(prefetch, 'path_node_id')})
            ),
            _select(
                candidate,
                _pick(candidate, chosen_names, {'node_id': _c(candidate, 'target_id')}),
                joins=[q.cross_join(stats)],
                predicate=_cmp(_c(stats, 'total'), bound_limit, '<=')
            )
        )
    );
    chosen = q.cte_ref(list(selected.schema.fields));
    parent = walk.ref();
    child = chosen.ref();
    ancestry_step = _select(
        parent,
        _pick(parent, chosen_names, {'spec_idx': _c(parent, 'step_spec_idx')}),
        joins=[
            q.inner_join(
                child,
                _all(
                    [
                        _present(_c(child, 'parent_node_id')),
                        _cmp(_c(parent, 'depth'), _c(child, 'parent_depth')),
                        _cmp(_c(parent, 'bfs_ord'), _c(child, 'parent_bfs_ord')),
                        _cmp(_c(parent, 'node_id'), _c(child, 'parent_node_id'))
                    ]
                )
            )
        ]
    );
    q.define_cte(
        chosen,
        q.union(_select(selected, _pick(selected, chosen_names)), ancestry_step),
        recursive=True
    );
    plan = _plan_rows(prefetch, True);
    pn = q.unnest(_c(chosen, 'step_nodes'), q.field('id', q.uuid_type()));
    pe = q.unnest(_c(chosen, 'step_edges'), q.field('id', q.uuid_type()));
    node_ids = q.cte(
        q.except_(
            _select(
                chosen, [('id', _c(pn, 'id'))], joins=[q.cross_join(pn)], distinct=True
            ),
            _select(
                prefetch,
                _pick(prefetch, ['id']),
                predicate=_present(_c(prefetch, 'id'))
            )
        )
    );
    edge_ids = q.cte(
        _select(chosen, [('id', _c(pe, 'id'))], joins=[q.cross_join(pe)], distinct=True)
    );
    available_nodes = q.cte(
        q.union(
            _select(
                prefetch,
                _pick(prefetch, ['id']),
                predicate=_present(_c(prefetch, 'id'))
            ),
            _select(node_ids, _pick(node_ids, ['id']))
        )
    );
    complete_specs = [
        spec
        for spec in specs
        if len(spec.get('chain') or []) == 1
    ];
    complete_queries = [
        _select(
            walk,
            [
                ('origin_id', _c(walk, 'node_id')),
                ('spec_idx', q.int64(int(spec['idx'])))
            ],
            predicate=_all(
                [
                    _c(walk, 'is_frontier'),
                    _cmp(_c(walk, 'depth'), bound_depth, '<'),
                    _match(_c(walk, 'arch_type'), _expected(spec.get('from_type')))
                ]
            ),
            distinct=True
        ) for spec in complete_specs
    ];
    complete_origins = q.cte(
        _union(complete_queries)
            if complete_queries
            else _select(
                None,
                [
                    ('origin_id', q.null(q.uuid_type())),
                    ('spec_idx', q.null(q.int64_type()))
                ],
                predicate=q.boolean(False)
            )
    );
    exp_edges = q.unnest(_c(candidate, 'step_edges'), q.field('id', q.uuid_type()));
    relevant = _either(
        [
            _cmp(_c(candidate, 'spec_idx'), q.int64(int(spec['idx'])))
            for spec in complete_specs
        ]
    );
    expected = q.cte(
        _select(
            candidate,
            [
                ('origin_id', _c(candidate, 'parent_node_id')),
                ('spec_idx', _c(candidate, 'spec_idx')),
                ('target_id', _c(candidate, 'target_id')),
                ('edge_id', _c(exp_edges, 'id')),
                ('group_complete', _c(candidate, 'group_complete'))
            ],
            joins=[q.cross_join(exp_edges)],
            predicate=_all([_present(_c(candidate, 'parent_node_id')), relevant])
        )
    );
    complete_hops = _complete_rows(
        complete_origins, expected, available_nodes, edge_ids, complete_optimization
    );
    topology_nodes = _topology_rows(node_ids, False);
    topology_edges = _topology_rows(edge_ids, True);
    result = _union(
        [
            _output(plan, 0),
            _output(topology_nodes, 1),
            _output(topology_edges, 2),
            _output(complete_hops, 3)
        ]
    );
    outputs = {
        f.name: q.Field(name=f.name, dtype=f.dtype) for f in result.ast.schema.fields
    };
    return q.compile_sql(
        q.ordered(
            result,
            [
                q.asc(q.output(outputs['row_kind'])),
                q.asc(q.output(outputs['ord']), nulls='LAST'),
                q.asc(q.output(outputs['seq']), nulls='FIRST'),
                q.asc(q.output(outputs['id']))
            ]
        )
    );
}

def _plan_rows(prefetch: any, specialized: bool) -> any {
    anchors = _anchors();
    ancestry = q.optional_source(_types());
    columns = _pick(
        prefetch, ['ord', 'id'] + (['depth'] if specialized else []) + ['is_frontier']
    );
    columns += [
        ('arch_type', _c(anchors, 'arch_type')),
        ('owner_root', _owner(anchors)),
        (
            'ancestors',
            q.coalesce(
                q.string_agg(_c(ancestry, 'ancestor'), q.text(','), distinct=True),
                _c(anchors, 'arch_type')
            )
        )
    ];
    groups = [
        _c(prefetch, k)
        for k in (['ord', 'id'] + (['depth'] if specialized else []) + ['is_frontier'])
    ];
    groups += [_c(anchors, k) for k in ['id', 'kind', 'arch_type', 'root_id']];
    return q.cte(
        _select(
            prefetch,
            columns,
            joins=[
                q.inner_join(
                    anchors,
                    _all(
                        [
                            _cmp(_c(anchors, 'id'), _c(prefetch, 'id')),
                            _cmp(_c(anchors, 'kind'), q.text('NodeAnchor'))
                        ]
                    )
                ),
                q.left_join(
                    ancestry, _cmp(_c(ancestry, 'type_name'), _c(anchors, 'arch_type'))
                )
            ],
            groups=groups
        )
    );
}

def _topology_rows(ids: any, edges: bool) -> any {
    anchors = _anchors();
    ancestry = q.optional_source(_types());
    names = ['id', 'arch_type']
        + (['src', 'dst', 'undirected', 'seq'] if edges else []);
    columns = _pick(anchors, names)
        + ([] if edges else [('owner_root', _owner(anchors))]);
    columns += [
        (
            'ancestors',
            q.coalesce(
                q.string_agg(_c(ancestry, 'ancestor'), q.text(','), distinct=True),
                _c(anchors, 'arch_type')
            )
        )
    ];
    groups = [
        _c(anchors, k)
        for k in (
            ['id', 'arch_type', 'src', 'dst', 'undirected', 'seq']
                if edges
                else ['id', 'kind', 'arch_type', 'root_id']
        )
    ];
    return q.cte(
        _select(
            anchors,
            columns,
            joins=[
                q.inner_join(ids, _cmp(_c(ids, 'id'), _c(anchors, 'id'))),
                q.left_join(
                    ancestry, _cmp(_c(ancestry, 'type_name'), _c(anchors, 'arch_type'))
                )
            ],
            predicate=_cmp(
                _c(anchors, 'kind'), q.text('EdgeAnchor' if edges else 'NodeAnchor')
            ),
            groups=groups
        )
    );
}

def _complete_rows(
    origins: any,
    expected: any,
    available_nodes: any,
    available_edges: any,
    optimized: bool
) -> any {
    if optimized {
        nodes = q.optional_source(available_nodes.ref());
        edges = q.optional_source(available_edges.ref());
        all_available = q.bool_and(
            _all(
                [
                    _c(expected, 'group_complete'),
                    _present(_c(nodes, 'id')),
                    _present(_c(edges, 'id'))
                ]
            )
        );
        status = q.cte(
            _select(
                expected,
                _pick(expected, ['origin_id', 'spec_idx'])
                    + [('all_available', all_available)],
                joins=[
                    q.left_join(
                        nodes, _cmp(_c(nodes, 'id'), _c(expected, 'target_id'))
                    ),
                    q.left_join(edges, _cmp(_c(edges, 'id'), _c(expected, 'edge_id')))
                ],
                groups=[_c(expected, 'origin_id'), _c(expected, 'spec_idx')]
            )
        );
        optional_status = q.optional_source(status);
        join = q.left_join(
            optional_status,
            _all(
                [
                    _cmp(_c(optional_status, 'origin_id'), _c(origins, 'origin_id')),
                    _cmp(_c(optional_status, 'spec_idx'), _c(origins, 'spec_idx'))
                ]
            )
        );
        return q.cte(
            _select(
                origins,
                _pick(origins, ['origin_id', 'spec_idx']),
                joins=[join],
                predicate=_all(
                    [
                        _present(_c(origins, 'origin_id')),
                        _present(_c(origins, 'spec_idx')),
                        _c(optional_status, 'all_available')
                    ]
                )
            )
        );
    }
    exp1 = expected.ref();
    exp2 = expected.ref();
    nodes = available_nodes.ref();
    edges = available_edges.ref();
    existing = q.exists(
        _select(
            exp1,
            [('one', q.int64(1))],
            predicate=_all(
                [
                    _cmp(_c(exp1, 'origin_id'), _c(origins, 'origin_id')),
                    _cmp(_c(exp1, 'spec_idx'), _c(origins, 'spec_idx'))
                ]
            )
        )
    );
    node_missing = q.not_(
        q.exists(
            _select(
                nodes,
                [('one', q.int64(1))],
                predicate=_cmp(_c(nodes, 'id'), _c(exp2, 'target_id'))
            )
        )
    );
    edge_missing = q.not_(
        q.exists(
            _select(
                edges,
                [('one', q.int64(1))],
                predicate=_cmp(_c(edges, 'id'), _c(exp2, 'edge_id'))
            )
        )
    );
    bad = q.exists(
        _select(
            exp2,
            [('one', q.int64(1))],
            predicate=_all(
                [
                    _cmp(_c(exp2, 'origin_id'), _c(origins, 'origin_id')),
                    _cmp(_c(exp2, 'spec_idx'), _c(origins, 'spec_idx')),
                    _either(
                        [
                            _negated(_c(exp2, 'group_complete')),
                            node_missing,
                            edge_missing
                        ]
                    )
                ]
            )
        )
    );
    return q.cte(
        _select(
            origins,
            _pick(origins, ['origin_id', 'spec_idx']),
            predicate=_all(
                [
                    _present(_c(origins, 'origin_id')),
                    _present(_c(origins, 'spec_idx')),
                    existing,
                    q.not_(bad)
                ]
            )
        )
    );
}

def _output(source: any, kind: int) -> any {
    return _select(
        source,
        [
            ('row_kind', q.int64(kind)),
            ('ord', _c(source, 'ord') if kind == 0 else q.null(q.int64_type())),
            ('id', _c(source, 'origin_id' if kind == 3 else 'id')),
            (
                'arch_type',
                q.null(q.text_type()) if kind == 3 else _c(source, 'arch_type')
            ),
            (
                'owner_root',
                _c(source, 'owner_root') if kind in (0, 1) else q.null(q.uuid_type())
            ),
            ('src', _c(source, 'src') if kind == 2 else q.null(q.uuid_type())),
            ('dst', _c(source, 'dst') if kind == 2 else q.null(q.uuid_type())),
            (
                'undirected',
                _c(source, 'is_frontier')
                    if kind == 0
                    else (_c(source, 'undirected') if kind == 2 else q.boolean(False))
            ),
            (
                'ancestors',
                q.null(q.text_type()) if kind == 3 else _c(source, 'ancestors')
            ),
            (
                'seq',
                _c(source, 'depth')
                    if kind == 0
                    else (
                        _c(source, 'seq')
                            if kind == 2
                            else (
                                _c(source, 'spec_idx')
                                    if kind == 3
                                    else q.null(q.int64_type())
                            )
                    )
            )
        ]
    );
}

def _build_layered(
    specs: list[dict], has_undirected: bool, include_roots: bool = False
) -> q.CompiledSQL {
    spec_fields = [
        q.field('idx', q.int64_type()),
        q.field('from_type', q.nullable(q.text_type())),
        q.field('is_visit', q.bool_type()),
        q.field('chain_len', q.int64_type())
    ];
    hop_fields = [
        q.field('spec_idx', q.int64_type()),
        q.field('hop_idx', q.int64_type()),
        q.field('edge_type', q.nullable(q.text_type())),
        q.field('node_type', q.nullable(q.text_type())),
        q.field('direction', q.int64_type())
    ];
    spec_rows: list[any] = [];
    hop_rows: list[any] = [];
    directions: list[int] = [];
    for spec in specs {
        chain = spec.get('chain') or [];
        idx = int(spec['idx']);
        spec_rows.append(
            [
                q.int64(idx),
                _expected(spec.get('from_type')),
                q.boolean(bool(spec.get('is_visit'))),
                q.int64(len(chain))
            ]
        );
        for (hop_idx, hop) in enumerate(chain) {
            direction = int(hop[2] or 2);
            directions.append(direction);
            hop_rows.append(
                [
                    q.int64(idx),
                    q.int64(hop_idx),
                    _expected(hop[0]),
                    _expected(hop[1]),
                    q.int64(direction)
                ]
            );
        }
    }
    spec_source = q.cte(q.values(spec_fields, spec_rows));
    hops = q.cte(q.values(hop_fields, hop_rows));
    seeds = q.unnest(
        q.slot('frontier_ids', q.array_type(q.uuid_type())),
        q.field('id', q.uuid_type()),
        q.field('ord', q.int64_type())
    );
    seed_node = _anchors();
    frontier = q.cte(
        _select(
            seeds,
            [('node_id', _c(seeds, 'id')), ('frontier_ord', _c(seeds, 'ord'))],
            joins=[
                q.inner_join(
                    seed_node,
                    _all(
                        [
                            _cmp(_c(seed_node, 'id'), _c(seeds, 'id')),
                            _cmp(_c(seed_node, 'kind'), q.text('NodeAnchor'))
                        ]
                    )
                )
            ]
        )
    );
    walk_fields = [
        q.field('spec_idx', q.int64_type()),
        q.field('chain_len', q.int64_type()),
        q.field('is_visit', q.bool_type()),
        q.field('seed_ord', q.int64_type()),
        q.field('hop_idx', q.int64_type()),
        q.field('node_id', q.uuid_type()),
        q.field('path_nodes', q.array_type(q.uuid_type())),
        q.field('hop_ord', q.array_type(q.int64_type()))
    ];
    walk = q.cte_ref(walk_fields);
    current = _anchors();
    anchor = _select(
        frontier,
        [
            ('spec_idx', _c(spec_source, 'idx')),
            ('chain_len', _c(spec_source, 'chain_len')),
            ('is_visit', _c(spec_source, 'is_visit')),
            ('seed_ord', _c(frontier, 'frontier_ord')),
            ('hop_idx', q.int64(0)),
            ('node_id', _c(frontier, 'node_id')),
            ('path_nodes', q.array(q.uuid_type(), [_c(frontier, 'node_id')])),
            ('hop_ord', q.array(q.int64_type(), []))
        ],
        joins=[
            q.inner_join(
                current,
                _all(
                    [
                        _cmp(_c(current, 'id'), _c(frontier, 'node_id')),
                        _cmp(_c(current, 'kind'), q.text('NodeAnchor'))
                    ]
                )
            ),
            q.inner_join(
                spec_source,
                _all(
                    [
                        _cmp(_c(spec_source, 'chain_len'), q.int64(0), '>'),
                        _match(_c(current, 'arch_type'), _c(spec_source, 'from_type'))
                    ]
                )
            )
        ]
    );
    edge_source = _anchors();
    target = _anchors();
    base_conditions = [
        _cmp(_c(edge_source, 'kind'), q.text('EdgeAnchor')),
        _present(_c(edge_source, 'src')),
        _present(_c(edge_source, 'dst'))
    ];
    direct_out = not has_undirected and all([d == 2 for d in directions]);
    direct_in = not has_undirected and all([d == 1 for d in directions]);
    if direct_out or direct_in {
        base_conditions.append(
            _cmp(_c(edge_source, 'src' if direct_out else 'dst'), _c(walk, 'node_id'))
        );
        target_id = _c(edge_source, 'dst' if direct_out else 'src');
    } else {
        base_conditions.append(
            _either(
                [
                    _all(
                        [
                            q.in_(_c(hops, 'direction'), [q.int64(2), q.int64(3)]),
                            _cmp(_c(edge_source, 'src'), _c(walk, 'node_id'))
                        ]
                    ),
                    _all(
                        [
                            q.in_(_c(hops, 'direction'), [q.int64(1), q.int64(3)]),
                            _cmp(_c(edge_source, 'dst'), _c(walk, 'node_id'))
                        ]
                    ),
                    _all(
                        [
                            _cmp(_c(hops, 'direction'), q.int64(1)),
                            _c(edge_source, 'undirected'),
                            _cmp(_c(edge_source, 'src'), _c(walk, 'node_id'))
                        ]
                    ),
                    _all(
                        [
                            _cmp(_c(hops, 'direction'), q.int64(2)),
                            _c(edge_source, 'undirected'),
                            _cmp(_c(edge_source, 'dst'), _c(walk, 'node_id'))
                        ]
                    )
                ]
            )
        );
        target_id = q.case_(
            [
                (
                    _cmp(_c(edge_source, 'src'), _c(walk, 'node_id')),
                    _c(edge_source, 'dst')
                )
            ],
            _c(edge_source, 'src')
        );
    }
    step = _select(
        walk,
        _pick(walk, ['spec_idx', 'chain_len', 'is_visit', 'seed_ord'])
            + [
                ('hop_idx', q.add(_c(hops, 'hop_idx'), q.int64(1))),
                ('node_id', _c(target, 'id')),
                (
                    'path_nodes',
                    q.array_append(_c(walk, 'path_nodes'), _c(target, 'id'))
                ),
                (
                    'hop_ord',
                    q.array_append(
                        _c(walk, 'hop_ord'),
                        q.coalesce(_c(edge_source, 'seq'), q.int64(0))
                    )
                )
            ],
        joins=[
            q.inner_join(
                hops,
                _all(
                    [
                        _cmp(_c(hops, 'spec_idx'), _c(walk, 'spec_idx')),
                        _cmp(_c(hops, 'hop_idx'), _c(walk, 'hop_idx'))
                    ]
                )
            ),
            q.inner_join(edge_source, _all(base_conditions)),
            q.inner_join(
                target,
                _all(
                    [
                        _cmp(_c(target, 'id'), target_id),
                        _cmp(_c(target, 'kind'), q.text('NodeAnchor'))
                    ]
                )
            )
        ],
        predicate=_all(
            [
                _cmp(_c(walk, 'hop_idx'), _c(walk, 'chain_len'), '<'),
                _match(_c(edge_source, 'arch_type'), _c(hops, 'edge_type')),
                _match(_c(target, 'arch_type'), _c(hops, 'node_type')),
                _negated(q.any_eq(_c(target, 'id'), _c(walk, 'path_nodes')))
            ]
        )
    );
    q.define_cte(walk, q.union_all(anchor, step), recursive=True);
    seed_rows = _select(
        frontier,
        [
            ('phase', q.int64(0)),
            ('seed_ord', _c(frontier, 'frontier_ord')),
            ('spec_idx', q.int64(-1)),
            ('hop_ord', q.array(q.int64_type(), [])),
            ('target_id', _c(frontier, 'node_id')),
            ('is_frontier', q.boolean(False))
        ]
    );
    visited_rows = _select(
        walk,
        [('phase', q.int64(1))]
            + _pick(walk, ['seed_ord', 'spec_idx', 'hop_ord'])
            + [
                ('target_id', _c(walk, 'node_id')),
                ('is_frontier', _c(walk, 'is_visit'))
            ],
        predicate=_cmp(_c(walk, 'hop_idx'), _c(walk, 'chain_len'))
    );
    candidates = q.cte(q.union_all(seed_rows, visited_rows));
    anchors = _anchors();
    node_rows = q.cte(
        _select(
            candidates,
            _pick(candidates, _names(candidates)) + [('owner_root', _owner(anchors))],
            joins=[
                q.inner_join(
                    anchors,
                    _all(
                        [
                            _cmp(_c(anchors, 'id'), _c(candidates, 'target_id')),
                            _cmp(_c(anchors, 'kind'), q.text('NodeAnchor'))
                        ]
                    )
                )
            ]
        )
    );
    ordering_names = ['phase', 'seed_ord', 'spec_idx', 'hop_ord'];
    additions = q.cte(
        q.union_all(
            _select(
                node_rows,
                _pick(node_rows, ordering_names)
                    + [
                        ('sub_ord', q.int64(0)),
                        ('id', _c(node_rows, 'target_id')),
                        ('is_frontier', _c(node_rows, 'is_frontier'))
                    ]
            ),
            _select(
                node_rows,
                _pick(node_rows, ordering_names)
                    + [
                        ('sub_ord', q.int64(1)),
                        ('id', _c(node_rows, 'owner_root')),
                        ('is_frontier', q.boolean(False))
                    ],
                predicate=_all(
                    [
                        _present(_c(node_rows, 'owner_root')),
                        q.boolean(include_roots),
                        _cmp(
                            _c(node_rows, 'owner_root'),
                            _c(node_rows, 'target_id'),
                            '<>'
                        )
                    ]
                )
            )
        )
    );
    seen_array = q.slot('seen_ids', q.array_type(q.uuid_type()));
    filtered = q.cte(
        _select(
            additions,
            _pick(additions, _names(additions)),
            predicate=_all(
                [
                    _present(_c(additions, 'id')),
                    _either(
                        [
                            q.slot('seen_empty', q.bool_type()),
                            _negated(q.any_eq(_c(additions, 'id'), seen_array))
                        ]
                    )
                ]
            )
        )
    );
    dedup = q.cte(
        _select(
            filtered,
            _pick(filtered, ['id'] + ordering_names + ['sub_ord', 'is_frontier']),
            distinct_on=[_c(filtered, 'id')],
            order=[
                q.asc(_c(filtered, k)) for k in (['id'] + ordering_names + ['sub_ord'])
            ]
        )
    );
    ordered_plan = q.cte(
        _select(
            dedup,
            _pick(dedup, ['id', 'is_frontier'])
                + [
                    (
                        'ord',
                        q.row_number(
                            order_by=[
                                q.asc(_c(dedup, k))
                                for k in (ordering_names + ['sub_ord', 'id'])
                            ]
                        )
                    )
                ]
        )
    );
    prefetch = q.cte(
        _select(
            ordered_plan,
            _pick(ordered_plan, _names(ordered_plan)),
            predicate=_cmp(
                _c(ordered_plan, 'ord'), q.slot('limit', q.int64_type()), '<='
            )
        )
    );
    plan = _plan_rows(prefetch, False);
    return q.compile_sql(
        _select(
            plan,
            _pick(
                plan,
                ['ord', 'id', 'arch_type', 'owner_root', 'ancestors', 'is_frontier']
            ),
            order=[q.asc(_c(plan, 'ord'))]
        )
    );
}

def compile_undirected_probe -> q.CompiledSQL {
    edges = _anchors();
    query = _select(
        edges,
        [('one', q.int64(1))],
        predicate=_all(
            [_cmp(_c(edges, 'kind'), q.text('EdgeAnchor')), _c(edges, 'undirected')]
        )
    );
    return q.compile_sql(_select(None, [('present', q.exists(q.limit_one(query)))]));
}


def _spec_key(specs: list[dict]) -> tuple[any, ...] {
    return tuple(
        (
            int(spec['idx']),
            spec.get('from_type'),
            bool(spec.get('is_visit')),
            tuple(
                (hop[0], hop[1], int(hop[2] or 2)) for hop in (spec.get('chain') or [])
            )
        ) for spec in specs
    );
}

def _specs_from_key(key: tuple[any, ...]) -> list[dict] {
    return [
        {'idx': item[0], 'from_type': item[1], 'is_visit': item[2], 'chain': item[3]}
        for item in key
    ];
}

@lru_cache(maxsize=128)
def _specialized_plan(
    key: tuple[any, ...], include_roots: bool, complete_optimization: bool
) -> q.CompiledSQL {
    return _build_specialized(
        _specs_from_key(key), include_roots, complete_optimization
    );
}

@lru_cache(maxsize=128)
def _layered_plan(
    key: tuple[any, ...], has_undirected: bool, include_roots: bool
) -> q.CompiledSQL {
    return _build_layered(_specs_from_key(key), has_undirected, include_roots);
}

def compile_specialized(
    specs: list[dict],
    origins: list[UUID],
    limit: int,
    max_depth: int,
    include_roots: bool = False,
    complete_optimization: bool = True
) -> q.CompiledSQL {
    plan = _specialized_plan(_spec_key(specs), include_roots, complete_optimization);
    return plan.bind(
        {'origin_ids': tuple(origins), 'limit': limit, 'max_depth': max_depth}
    );
}

def compile_layered(
    specs: list[dict],
    frontier_ids: list[UUID],
    seen_ids: list[UUID],
    limit: int,
    has_undirected: bool,
    include_roots: bool = False
) -> q.CompiledSQL {
    plan = _layered_plan(_spec_key(specs), has_undirected, include_roots);
    return plan.bind(
        {
            'frontier_ids': tuple(frontier_ids),
            'seen_ids': tuple(seen_ids),
            'seen_empty': not bool(seen_ids),
            'limit': limit
        }
    );
}
