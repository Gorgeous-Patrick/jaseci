"""Frozen SQL comparison oracle from TTG commit 758366971.

Keep this baseline independent from the structured generator.
"""
def _ttg_sql_type_match(expr: str, param: str) -> str {
    return (
        f"(CAST(:{param} AS text) IS NULL "
        f"OR {expr} = CAST(:{param} AS text) "
        "OR EXISTS ("
        "SELECT 1 FROM graph_types gt "
        f"WHERE gt.type_name = {expr} "
        f"AND gt.ancestor = CAST(:{param} AS text)"
        "))"
    );
}


def _ttg_sql_bool(value: bool) -> str {
    return "TRUE" if value else "FALSE";
}


def _ttg_render_directed_edge_branch(
    source_expr: str,
    source_col: str,
    target_col: str,
    edge_param: str,
    node_param: str
) -> str {
    target_expr = f"edge.{target_col}";
    return f"""
                    SELECT
                        edge.id AS edge_id,
                        COALESCE(edge.seq, 0)::bigint AS edge_seq,
                        tgt.id AS node_id,
                        tgt.arch_type AS arch_type
                    FROM anchors edge
                    JOIN anchors tgt
                        ON tgt.id = {target_expr}
                       AND tgt.kind = 'NodeAnchor'
                    WHERE edge.kind = 'EdgeAnchor'
                      AND edge.{source_col} = {source_expr}
                      AND {target_expr} IS NOT NULL
                      AND {_ttg_sql_type_match("edge.arch_type", edge_param)}
                      AND {_ttg_sql_type_match("tgt.arch_type", node_param)}
            """;
}


def _ttg_render_hop_join(
    spec_idx: int,
    hop_idx: int,
    source_expr: str,
    prior_nodes: list[str],
    hop: tuple[str | None, str | None, int],
    params: dict[str, object],
    frontier_alias: str = "walk"
) -> str {
    alias = f"s{spec_idx}h{hop_idx}";
    edge_param = f"{alias}edge";
    node_param = f"{alias}node";
    params[edge_param] = hop[0];
    params[node_param] = hop[1];
    direction = int(hop[2] or 2);
    branches: list[str] = [];
    if direction in (2, 3) {
        branches.append(
            _ttg_render_directed_edge_branch(
                source_expr, "src", "dst", edge_param, node_param
            )
        );
    }
    if direction in (1, 3) {
        branches.append(
            _ttg_render_directed_edge_branch(
                source_expr, "dst", "src", edge_param, node_param
            )
        );
    }
    if not branches {
        raise RuntimeError(
            f"TTG specialized set-based SQL cannot lower direction {direction}"
        );
    }
    edge_sql = "\n                    UNION ALL\n".join(branches);
    cycle_terms: list[str] = [];
    if frontier_alias {
        cycle_terms.append(
            f"NOT ({alias}_edges.node_id = ANY({frontier_alias}.path_nodes))"
        );
    }
    cycle_terms.append(f"{alias}_edges.node_id <> {source_expr}");
    cycle_terms.extend([f"{alias}_edges.node_id <> {n}" for n in prior_nodes]);
    cycle_sql = " AND ".join(cycle_terms) if cycle_terms else "TRUE";
    return f"""
                JOIN LATERAL (
                    SELECT *
                    FROM (
                        {edge_sql}
                    ) {alias}_edges
                    WHERE {cycle_sql}
                ) {alias} ON TRUE
            """;
}


def _ttg_hop_key_expr(alias: str) -> str {
    return (
        "CONCAT("
        f"LPAD(CAST({alias}.edge_seq AS text), 20, '0'), "
        "':', "
        f"{alias}.edge_id::text"
        ")"
    );
}


def _ttg_edge_id_expr(alias: str) -> str {
    return f"{alias}.edge_id";
}


def _ttg_render_spec_select(
    spec: dict[str, object],
    params: dict[str, object]
) -> str {
    import from typing { cast }
    spec_idx = int(spec["idx"]);
    pfx = f"s{spec_idx}";
    params[f"{pfx}from"] = spec.get("from_type");
    chain = cast(
        list[tuple[str | None, str | None, int]],
        spec.get("chain") or []
    );
    prior_nodes: list[str] = [];
    source_expr = "walk.node_id";
    hop_joins: list[str] = [];
    hop_keys: list[str] = [];
    edge_ids: list[str] = [];
    hop_aliases: list[str] = [];
    for (hop_idx, hop) in enumerate(chain) {
        alias = f"s{spec_idx}h{hop_idx}";
        hop_aliases.append(alias);
        hop_joins.append(
            _ttg_render_hop_join(
                spec_idx, hop_idx, source_expr, prior_nodes, hop, params
            )
        );
        hop_keys.append(_ttg_hop_key_expr(alias));
        edge_ids.append(_ttg_edge_id_expr(alias));
        source_expr = f"{alias}.node_id";
        prior_nodes.append(source_expr);
    }
    if not hop_joins {
        raise RuntimeError("TTG specialized set-based SQL requires non-empty chain");
    }
    last_node_expr = prior_nodes[-1];
    last_arch_type_expr = f"{hop_aliases[-1]}.arch_type";
    path_nodes_sql = ", ".join(prior_nodes);
    hop_key_sql = ", ".join(hop_keys);
    edge_ids_sql = ", ".join(edge_ids);
    visit_sql = _ttg_sql_bool(bool(spec.get("is_visit")));
    return f"""
                        SELECT
                            {spec_idx}::int AS spec_idx,
                            {visit_sql}::boolean AS is_visit,
                            {last_node_expr} AS next_id,
                            {last_arch_type_expr} AS next_arch_type,
                            walk.path_nodes
                                || ARRAY[{path_nodes_sql}]::uuid[] AS path_nodes,
                            walk.path_edges
                                || ARRAY[{edge_ids_sql}]::uuid[] AS path_edges,
                            ARRAY[{hop_key_sql}]::text[] AS hop_ord
                        FROM (
                            SELECT 1
                            WHERE {_ttg_sql_type_match("walk.arch_type", f"{pfx}from")}
                        ) spec_gate
                        {" ".join(hop_joins)}
            """;
}


def _ttg_render_frontier_spec_select(
    spec: dict[str, object],
    params: dict[str, object]
) -> str {
    import from typing { cast }
    spec_idx = int(spec["idx"]);
    pfx = f"s{spec_idx}";
    params[f"{pfx}from"] = spec.get("from_type");
    chain = cast(
        list[tuple[str | None, str | None, int]],
        spec.get("chain") or []
    );
    prior_nodes: list[str] = [];
    source_expr = "frontier.node_id";
    hop_joins: list[str] = [];
    hop_keys: list[str] = [];
    edge_ids: list[str] = [];
    hop_aliases: list[str] = [];
    for (hop_idx, hop) in enumerate(chain) {
        alias = f"s{spec_idx}h{hop_idx}";
        hop_aliases.append(alias);
        hop_joins.append(
            _ttg_render_hop_join(
                spec_idx, hop_idx, source_expr, prior_nodes, hop, params,
                ""
            )
        );
        hop_keys.append(_ttg_hop_key_expr(alias));
        edge_ids.append(_ttg_edge_id_expr(alias));
        source_expr = f"{alias}.node_id";
        prior_nodes.append(source_expr);
    }
    if not hop_joins {
        raise RuntimeError("TTG specialized set-based SQL requires non-empty chain");
    }
    last_node_expr = prior_nodes[-1];
    last_arch_type_expr = f"{hop_aliases[-1]}.arch_type";
    path_nodes_sql = ", ".join(prior_nodes);
    edge_ids_sql = ", ".join(edge_ids);
    step_ord_sql = " || ':' || ".join(hop_keys);
    visit_sql = _ttg_sql_bool(bool(spec.get("is_visit")));
    return f"""
                SELECT
                    frontier.depth + 1 AS depth,
                    {last_node_expr} AS node_id,
                    {last_arch_type_expr} AS arch_type,
                    frontier.depth AS parent_depth,
                    frontier.bfs_ord AS parent_bfs_ord,
                    frontier.node_id AS parent_node_id,
                    ARRAY[{path_nodes_sql}]::uuid[] AS step_nodes,
                    ARRAY[{edge_ids_sql}]::uuid[] AS step_edges,
                    ({step_ord_sql}) AS step_ord,
                    {visit_sql}::boolean AS is_frontier,
                    {spec_idx}::int AS spec_idx
                FROM frontier
                {" ".join(hop_joins)}
                WHERE {_ttg_sql_type_match("frontier.arch_type", f"{pfx}from")}
            """;
}


def _ttg_render_complete_origin_sql(
    specs: list[dict],
    params: dict[str, object]
) -> tuple[str, str] {
    complete_selects: list[str] = [];
    complete_spec_ids: list[str] = [];
    for spec in specs {
        chain = spec.get("chain") or [];
        if len(chain) != 1 {
            continue;
        }
        spec_idx = int(spec["idx"]);
        pfx = f"s{spec_idx}complete_from";
        params[pfx] = spec.get("from_type");
        complete_spec_ids.append(str(spec_idx));
        complete_selects.append(f"""
                SELECT DISTINCT
                    w.node_id AS origin_id,
                    {spec_idx}::int AS spec_idx
                FROM walk w
                WHERE w.is_frontier
                  AND w.depth < CAST(:max_depth AS int)
                  AND {_ttg_sql_type_match("w.arch_type", pfx)}
            """);
    }
    if not complete_selects {
        return (
            "SELECT NULL::uuid AS origin_id, NULL::int AS spec_idx WHERE FALSE",
            "FALSE"
        );
    }
    return (
        "\n                UNION ALL\n".join(complete_selects),
        f"c.spec_idx IN ({', '.join(complete_spec_ids)})"
    );
}


def _ttg_opt_complete_hops_enabled -> bool {
    import os as _os;
    raw = _os.environ.get("JAC_TTG_OPT_COMPLETE_HOPS", "").strip().lower();
    return raw not in ("0", "false", "no", "off");
}


def _ttg_prefetch_owner_roots_enabled -> bool {
    import os as _os;
    raw = _os.environ.get("JAC_TTG_PREFETCH_OWNER_ROOTS", "").strip().lower();
    return raw in ("1", "true", "yes", "on");
}


def _ttg_render_complete_hop_rows_sql -> str {
    if _ttg_opt_complete_hops_enabled() {
        return """
            expected_complete_status AS (
                SELECT
                    exp.origin_id,
                    exp.spec_idx,
                    BOOL_AND(
                        exp.group_complete
                        AND an.id IS NOT NULL
                        AND ae.id IS NOT NULL
                    )
                        AS all_available
                FROM expected_complete_edges exp
                LEFT JOIN available_node_ids an ON an.id = exp.target_id
                LEFT JOIN available_edge_ids ae ON ae.id = exp.edge_id
                GROUP BY exp.origin_id, exp.spec_idx
            ),
            complete_hop_rows AS (
                SELECT
                    co.origin_id,
                    co.spec_idx
                FROM complete_origins co
                LEFT JOIN expected_complete_status ecs
                  ON ecs.origin_id = co.origin_id
                 AND ecs.spec_idx = co.spec_idx
                WHERE co.origin_id IS NOT NULL
                  AND co.spec_idx IS NOT NULL
                  AND ecs.all_available
            )""";
    }
    return """
            complete_hop_rows AS (
                SELECT
                    co.origin_id,
                    co.spec_idx
                FROM complete_origins co
                WHERE co.origin_id IS NOT NULL
                  AND co.spec_idx IS NOT NULL
                  AND EXISTS (
                      SELECT 1
                      FROM expected_complete_edges exp
                      WHERE exp.origin_id = co.origin_id
                        AND exp.spec_idx = co.spec_idx
                  )
                  AND NOT EXISTS (
	                      SELECT 1
	                      FROM expected_complete_edges exp
	                      WHERE exp.origin_id = co.origin_id
	                        AND exp.spec_idx = co.spec_idx
	                        AND (
	                            NOT exp.group_complete
	                            OR NOT EXISTS (
	                                SELECT 1
	                                FROM available_node_ids an
	                                WHERE an.id = exp.target_id
	                            )
                            OR NOT EXISTS (
                                SELECT 1
                                FROM available_edge_ids ae
                                WHERE ae.id = exp.edge_id
                            )
                        )
                  )
            )""";
}


def _ttg_render_specialized_set_based_sql(
    specs: list[dict],
    params: dict[str, object]
) -> str {
    params["include_owner_roots"] = _ttg_prefetch_owner_roots_enabled();
    frontier_selects = [
        _ttg_render_frontier_spec_select(spec, params)
        for spec in specs
    ];
    recursive_sql = "\n                UNION ALL\n".join(frontier_selects);
    (complete_origin_sql, complete_expected_filter) = _ttg_render_complete_origin_sql(
        specs, params
    );
    complete_hop_rows_sql = _ttg_render_complete_hop_rows_sql();
    return f"""
	            WITH RECURSIVE
	            walk(
	                depth,
	                bfs_ord,
	                node_id,
	                arch_type,
	                parent_depth,
	                parent_bfs_ord,
	                parent_node_id,
	                step_nodes,
	                step_edges,
	                is_frontier,
	                step_spec_idx,
	                step_group_complete
	            ) AS (
	                SELECT
	                    0::int AS depth,
	                    seed.ord::bigint AS bfs_ord,
	                    seed.id AS node_id,
	                    n.arch_type AS arch_type,
	                    NULL::int AS parent_depth,
	                    NULL::bigint AS parent_bfs_ord,
	                    NULL::uuid AS parent_node_id,
	                    ARRAY[seed.id]::uuid[] AS step_nodes,
	                    ARRAY[]::uuid[] AS step_edges,
	                    TRUE AS is_frontier,
	                    NULL::int AS step_spec_idx,
	                    TRUE AS step_group_complete
	                FROM unnest(CAST(:origin_ids AS uuid[]))
	                    WITH ORDINALITY AS seed(id, ord)
	                JOIN anchors n ON n.id = seed.id
	                 AND n.kind = 'NodeAnchor'
	                UNION ALL
	                SELECT
	                    ranked.depth,
	                    ranked.local_rank::bigint AS bfs_ord,
	                    ranked.node_id,
	                    ranked.arch_type,
	                    ranked.parent_depth,
	                    ranked.parent_bfs_ord,
	                    ranked.parent_node_id,
	                    ranked.step_nodes,
	                    ranked.step_edges,
	                    (
	                        ranked.is_frontier
	                        AND ranked.layer_count < CAST(:limit AS bigint)
	                    ) AS is_frontier,
	                    ranked.spec_idx,
	                    ranked.group_complete
	                FROM (
	                    SELECT
	                        raw_budgeted.*,
	                        ROW_NUMBER() OVER (
	                            ORDER BY
	                                raw_budgeted.group_ord,
	                                raw_budgeted.group_row_rank,
	                                raw_budgeted.node_id
	                        ) AS local_rank,
	                        COUNT(*) OVER () AS layer_count
	                    FROM (
	                        WITH frontier AS MATERIALIZED (
	                            SELECT walk.*
	                            FROM walk
	                            WHERE walk.is_frontier
	                              AND walk.depth < CAST(:max_depth AS int)
	                        ),
	                        frontier_nodes AS MATERIALIZED (
	                            SELECT node_id
	                            FROM frontier
	                        ),
	                        raw AS (
	                            {recursive_sql}
	                        ),
	                        raw_annotated AS (
	                            SELECT
	                                raw.*,
	                                EXISTS (
	                                    SELECT 1
	                                    FROM frontier_nodes fn
	                                    WHERE fn.node_id = raw.node_id
	                                ) AS already_frontier,
	                                COUNT(*) OVER (
	                                    PARTITION BY
	                                        raw.parent_bfs_ord,
	                                        raw.spec_idx,
	                                        raw.parent_node_id
	                                ) AS raw_group_count
	                            FROM raw
	                        ),
	                        raw_unseen AS (
	                            SELECT *
	                            FROM raw_annotated
	                            WHERE NOT already_frontier
	                        ),
	                        raw_dedup AS (
	                            SELECT DISTINCT ON (node_id)
	                                raw_unseen.*
	                            FROM raw_unseen
	                            ORDER BY
	                                node_id,
	                                parent_bfs_ord,
	                                spec_idx,
	                                parent_node_id,
	                                step_ord
	                        ),
	                        raw_dedup_grouped AS (
	                            SELECT
	                                raw_dedup.*,
	                                COUNT(*) OVER (
	                                    PARTITION BY
	                                        raw_dedup.parent_bfs_ord,
	                                        raw_dedup.spec_idx,
	                                        raw_dedup.parent_node_id
	                                ) AS dedup_group_count
	                            FROM raw_dedup
	                        ),
	                        raw_grouped AS (
	                            SELECT
	                                raw_dedup_grouped.*,
	                                DENSE_RANK() OVER (
	                                    ORDER BY
	                                        raw_dedup_grouped.parent_bfs_ord,
	                                        raw_dedup_grouped.spec_idx,
	                                        raw_dedup_grouped.parent_node_id
	                                ) AS group_ord,
	                                ROW_NUMBER() OVER (
	                                    PARTITION BY
	                                        raw_dedup_grouped.parent_bfs_ord,
	                                        raw_dedup_grouped.spec_idx,
	                                        raw_dedup_grouped.parent_node_id
	                                    ORDER BY
	                                        raw_dedup_grouped.step_ord,
	                                        raw_dedup_grouped.node_id
	                                ) AS group_row_rank,
	                                COUNT(*) OVER (
	                                    PARTITION BY
	                                        raw_dedup_grouped.parent_bfs_ord,
	                                        raw_dedup_grouped.spec_idx,
	                                        raw_dedup_grouped.parent_node_id
	                                ) AS group_count
	                            FROM raw_dedup_grouped
	                        ),
	                        group_budget AS (
	                            SELECT
	                                groups.group_ord,
	                                groups.group_count,
	                                COALESCE(
	                                    SUM(groups.group_count) OVER (
	                                        ORDER BY groups.group_ord
	                                        ROWS BETWEEN UNBOUNDED PRECEDING
	                                            AND 1 PRECEDING
	                                    ),
	                                    0
	                                ) AS group_prior_count,
	                                SUM(groups.group_count) OVER (
	                                    ORDER BY groups.group_ord
	                                    ROWS BETWEEN UNBOUNDED PRECEDING
	                                        AND CURRENT ROW
	                                ) AS group_cume_count
	                            FROM (
	                                SELECT DISTINCT group_ord, group_count
	                                FROM raw_grouped
	                            ) groups
	                        )
	                        SELECT
	                            raw_grouped.*,
	                            group_budget.group_prior_count,
	                            group_budget.group_cume_count,
	                            (
	                                group_budget.group_cume_count
	                                <= CAST(:limit AS bigint)
	                                AND raw_grouped.dedup_group_count
	                                    = raw_grouped.raw_group_count
	                            ) AS group_complete
	                        FROM raw_grouped
	                        JOIN group_budget
	                          ON group_budget.group_ord = raw_grouped.group_ord
	                        WHERE group_budget.group_prior_count
	                              < CAST(:limit AS bigint)
	                          AND raw_grouped.group_row_rank
	                              <= (
	                                  CAST(:limit AS bigint)
	                                  - group_budget.group_prior_count
	                              )
	                    ) raw_budgeted
	                ) ranked
	            ),
	            candidate_node_rows AS (
	                SELECT
	                    walk.depth,
	                    walk.bfs_ord,
	                    walk.node_id AS target_id,
	                    walk.parent_depth,
	                    walk.parent_bfs_ord,
	                    walk.parent_node_id,
	                    walk.step_nodes,
	                    walk.step_edges,
	                    walk.is_frontier,
	                    walk.step_spec_idx AS spec_idx,
	                    walk.step_group_complete AS group_complete,
	                    CASE
	                        WHEN n.kind = 'NodeAnchor' AND n.arch_type = 'Root'
	                            THEN n.id
                        ELSE n.root_id
                    END AS owner_root
                FROM walk
                JOIN anchors n ON n.id = walk.node_id
                 AND n.kind = 'NodeAnchor'
            ),
	            raw_additions AS (
	                SELECT
	                    depth,
	                    bfs_ord,
	                    target_id AS path_node_id,
	                    parent_depth,
	                    parent_bfs_ord,
	                    parent_node_id,
	                    step_nodes,
	                    step_edges,
	                    spec_idx,
	                    0 AS sub_ord,
	                    target_id AS id,
	                    is_frontier
	                FROM candidate_node_rows
	                UNION ALL
	                SELECT
	                    depth,
	                    bfs_ord,
	                    target_id AS path_node_id,
	                    parent_depth,
	                    parent_bfs_ord,
	                    parent_node_id,
	                    step_nodes,
	                    step_edges,
	                    spec_idx,
	                    1 AS sub_ord,
	                    owner_root AS id,
	                    FALSE AS is_frontier
	                FROM candidate_node_rows
                WHERE owner_root IS NOT NULL
                  AND CAST(:include_owner_roots AS boolean)
                  AND owner_root <> target_id
            ),
            frontier_flags AS (
                SELECT
                    id,
                    BOOL_OR(is_frontier) AS is_frontier
                FROM raw_additions
                WHERE id IS NOT NULL
                GROUP BY id
            ),
            dedup_additions AS (
	                SELECT DISTINCT ON (id)
	                    raw_additions.id,
	                    raw_additions.depth,
	                    raw_additions.bfs_ord,
	                    raw_additions.path_node_id,
	                    raw_additions.parent_depth,
	                    raw_additions.parent_bfs_ord,
	                    raw_additions.parent_node_id,
	                    raw_additions.step_nodes,
	                    raw_additions.step_edges,
	                    raw_additions.spec_idx,
	                    raw_additions.sub_ord,
	                    frontier_flags.is_frontier
	                FROM raw_additions
	                JOIN frontier_flags ON frontier_flags.id = raw_additions.id
	                WHERE raw_additions.id IS NOT NULL
	                ORDER BY raw_additions.id, depth, bfs_ord, sub_ord
	            ),
	            ordered_plan AS (
	                SELECT
	                    id,
	                    depth,
	                    bfs_ord,
	                    path_node_id,
	                    parent_depth,
	                    parent_bfs_ord,
	                    parent_node_id,
	                    step_nodes,
	                    step_edges,
	                    spec_idx,
	                    is_frontier,
	                    ROW_NUMBER() OVER (
	                        ORDER BY depth, bfs_ord, sub_ord, id
	                    ) AS ord
	                FROM dedup_additions
	            ),
	            prefetch_plan AS (
	                SELECT
	                    id,
	                    depth,
	                    bfs_ord,
	                    path_node_id,
	                    parent_depth,
	                    parent_bfs_ord,
	                    parent_node_id,
	                    step_nodes,
	                    step_edges,
	                    spec_idx,
	                    is_frontier,
	                    ord
	                FROM ordered_plan
	                WHERE ord <= CAST(:limit AS bigint)
	            ),
	            plan_stats AS (
	                SELECT COUNT(*)::bigint AS total
	                FROM ordered_plan
	            ),
	            selected_path_rows AS (
	                SELECT
	                    p.depth,
	                    p.bfs_ord,
	                    p.path_node_id AS node_id,
	                    p.parent_depth,
	                    p.parent_bfs_ord,
	                    p.parent_node_id,
	                    p.step_nodes,
	                    p.step_edges,
	                    p.spec_idx
	                FROM prefetch_plan p
	                UNION ALL
	                SELECT
	                    c.depth,
	                    c.bfs_ord,
	                    c.target_id AS node_id,
	                    c.parent_depth,
	                    c.parent_bfs_ord,
	                    c.parent_node_id,
	                    c.step_nodes,
	                    c.step_edges,
	                    c.spec_idx
	                FROM candidate_node_rows c
	                CROSS JOIN plan_stats ps
	                WHERE ps.total <= CAST(:limit AS bigint)
	            ),
	            chosen_paths(
	                depth,
	                bfs_ord,
	                node_id,
	                parent_depth,
	                parent_bfs_ord,
	                parent_node_id,
	                step_nodes,
	                step_edges,
	                spec_idx
	            ) AS (
	                SELECT
	                    depth,
	                    bfs_ord,
	                    node_id,
	                    parent_depth,
	                    parent_bfs_ord,
	                    parent_node_id,
	                    step_nodes,
	                    step_edges,
	                    spec_idx
	                FROM selected_path_rows
	                UNION
	                SELECT
	                    parent.depth,
	                    parent.bfs_ord,
	                    parent.node_id,
	                    parent.parent_depth,
	                    parent.parent_bfs_ord,
	                    parent.parent_node_id,
	                    parent.step_nodes,
	                    parent.step_edges,
	                    parent.step_spec_idx
	                FROM walk parent
	                JOIN chosen_paths child
	                  ON child.parent_node_id IS NOT NULL
	                 AND parent.depth = child.parent_depth
	                 AND parent.bfs_ord = child.parent_bfs_ord
	                 AND parent.node_id = child.parent_node_id
	            ),
	            plan_rows AS (
	                SELECT
	                    p.ord,
                    p.id,
                    p.depth,
                    p.is_frontier,
                    n.arch_type,
                    CASE
                        WHEN n.kind = 'NodeAnchor' AND n.arch_type = 'Root'
                            THEN n.id
                        ELSE n.root_id
                    END AS owner_root,
                    COALESCE(string_agg(DISTINCT gt.ancestor, ','), n.arch_type)
                        AS ancestors
                FROM prefetch_plan p
                JOIN anchors n ON n.id = p.id
                 AND n.kind = 'NodeAnchor'
                LEFT JOIN graph_types gt ON gt.type_name = n.arch_type
                GROUP BY
                    p.ord,
                    p.id,
                    p.depth,
                    p.is_frontier,
                    n.id,
                    n.kind,
                    n.arch_type,
	                    n.root_id
	            ),
	            topology_node_ids AS (
	                SELECT DISTINCT pn.id
	                FROM chosen_paths p
	                CROSS JOIN LATERAL unnest(p.step_nodes) AS pn(id)
	                WHERE pn.id IS NOT NULL
	                EXCEPT
	                SELECT id
                FROM prefetch_plan
                WHERE id IS NOT NULL
            ),
	            topology_edge_ids AS (
	                SELECT DISTINCT pe.id
	                FROM chosen_paths p
	                CROSS JOIN LATERAL unnest(p.step_edges) AS pe(id)
	                WHERE pe.id IS NOT NULL
	            ),
	            available_node_ids AS (
	                SELECT id
	                FROM prefetch_plan
	                WHERE id IS NOT NULL
	                UNION
	                SELECT id
	                FROM topology_node_ids
	                WHERE id IS NOT NULL
	            ),
	            available_edge_ids AS (
	                SELECT id
	                FROM topology_edge_ids
	                WHERE id IS NOT NULL
	            ),
	            complete_origins AS (
	                {complete_origin_sql}
	            ),
	            expected_complete_edges AS (
	                SELECT
	                    c.parent_node_id AS origin_id,
	                    c.spec_idx,
	                    c.target_id AS target_id,
	                    edge_ids.id AS edge_id,
	                    c.group_complete
	                FROM candidate_node_rows c
	                CROSS JOIN LATERAL unnest(c.step_edges) AS edge_ids(id)
	                WHERE c.parent_node_id IS NOT NULL
	                  AND {complete_expected_filter}
	            ),
	            {complete_hop_rows_sql},
            topology_node_rows AS (
                SELECT
                    n.id,
                    n.arch_type,
                    CASE
                        WHEN n.kind = 'NodeAnchor' AND n.arch_type = 'Root'
                            THEN n.id
                        ELSE n.root_id
                    END AS owner_root,
                    COALESCE(string_agg(DISTINCT gt.ancestor, ','), n.arch_type)
                        AS ancestors
                FROM anchors n
                JOIN topology_node_ids t ON t.id = n.id
                LEFT JOIN graph_types gt ON gt.type_name = n.arch_type
                WHERE n.kind = 'NodeAnchor'
                GROUP BY n.id, n.kind, n.arch_type, n.root_id
            ),
            topology_edge_rows AS (
                SELECT
                    e.id,
                    e.arch_type,
                    e.src,
                    e.dst,
                    e.undirected,
                    COALESCE(string_agg(DISTINCT gt.ancestor, ','), e.arch_type)
                        AS ancestors,
                    e.seq
                FROM anchors e
                JOIN topology_edge_ids t ON t.id = e.id
                LEFT JOIN graph_types gt ON gt.type_name = e.arch_type
                WHERE e.kind = 'EdgeAnchor'
                GROUP BY e.id, e.arch_type, e.src, e.dst, e.undirected, e.seq
            )
            SELECT
                0::int AS row_kind,
                ord,
                id,
                arch_type,
                owner_root,
                NULL::uuid AS src,
                NULL::uuid AS dst,
                is_frontier AS undirected,
                ancestors,
                depth::bigint AS seq
            FROM plan_rows
            UNION ALL
            SELECT
                1::int AS row_kind,
                NULL::bigint AS ord,
                id,
                arch_type,
                owner_root,
                NULL::uuid AS src,
                NULL::uuid AS dst,
                false AS undirected,
                ancestors,
                NULL::bigint AS seq
            FROM topology_node_rows
            UNION ALL
            SELECT
                2::int AS row_kind,
                NULL::bigint AS ord,
                id,
                arch_type,
                NULL::uuid AS owner_root,
                src,
                dst,
                undirected,
                ancestors,
                seq
            FROM topology_edge_rows
            UNION ALL
            SELECT
                3::int AS row_kind,
                NULL::bigint AS ord,
                origin_id AS id,
                NULL::text AS arch_type,
                NULL::uuid AS owner_root,
                NULL::uuid AS src,
                NULL::uuid AS dst,
                false AS undirected,
                NULL::text AS ancestors,
                spec_idx::bigint AS seq
            FROM complete_hop_rows
            ORDER BY row_kind, ord NULLS LAST, seq NULLS FIRST, id
            """;
}



def layered_sql(specs: list[dict], max_length: int, has_undirected: bool) -> tuple[str,dict[str,object]] {
    max_chain_len = 1;
    for spec in specs {
        chain = spec.get("chain") or [];
        max_chain_len = max(max_chain_len, len(chain));
    }
    base_params: dict[str, object] = {
        "max_depth": int(max_length),
        "include_owner_roots": _ttg_prefetch_owner_roots_enabled()
    };
    spec_values: list[str] = [];
    hop_values: list[str] = [];
    all_outgoing = True;
    all_incoming = True;
    for spec in specs {
        idx = int(spec["idx"]);
        pfx = f"s{idx}";
        base_params[f"{pfx}idx"] = idx;
        base_params[f"{pfx}from"] = spec.get("from_type");
        base_params[f"{pfx}visit"] = bool(spec.get("is_visit"));
        chain = spec.get("chain") or [];
        base_params[f"{pfx}len"] = len(chain);
        spec_values.append(
            f"(CAST(:{pfx}idx AS int), CAST(:{pfx}from AS text), "
            f"CAST(:{pfx}visit AS boolean), CAST(:{pfx}len AS int))"
        );
        for (hop_idx, hop) in enumerate(chain) {
            hpfx = f"s{idx}h{hop_idx}";
            base_params[f"{hpfx}sidx"] = idx;
            base_params[f"{hpfx}hidx"] = hop_idx;
            base_params[f"{hpfx}edge"] = hop[0];
            base_params[f"{hpfx}node"] = hop[1];
            direction = int(hop[2] or 2);
            base_params[f"{hpfx}dir"] = direction;
            if direction != 2 {
                all_outgoing = False;
            }
            if direction != 1 {
                all_incoming = False;
            }
            hop_values.append(
                f"(CAST(:{hpfx}sidx AS int), CAST(:{hpfx}hidx AS int), "
                f"CAST(:{hpfx}edge AS text), CAST(:{hpfx}node AS text), "
                f"CAST(:{hpfx}dir AS int))"
            );
        }
    }
    spec_values_sql = ",\n                    ".join(spec_values);
    hop_values_sql = ",\n                    ".join(hop_values);
    direction_mode = "generic";
    if not has_undirected and all_outgoing {
        direction_mode = "directed-out";
        edge_step_sql = """
                JOIN anchors edge
                    ON edge.kind = 'EdgeAnchor'
                   AND edge.src = chain_walk.node_id
                   AND edge.src IS NOT NULL
                   AND edge.dst IS NOT NULL
                JOIN anchors tgt
                    ON tgt.id = edge.dst
                   AND tgt.kind = 'NodeAnchor'
                """;
    } elif not has_undirected and all_incoming {
        direction_mode = "directed-in";
        edge_step_sql = """
                JOIN anchors edge
                    ON edge.kind = 'EdgeAnchor'
                   AND edge.dst = chain_walk.node_id
                   AND edge.src IS NOT NULL
                   AND edge.dst IS NOT NULL
                JOIN anchors tgt
                    ON tgt.id = edge.src
                   AND tgt.kind = 'NodeAnchor'
                """;
    } else {
        edge_step_sql = """
                JOIN anchors edge
                    ON edge.kind = 'EdgeAnchor'
                   AND edge.src IS NOT NULL
                   AND edge.dst IS NOT NULL
                   AND (
                       (
                           hops.direction IN (2, 3)
                           AND edge.src = chain_walk.node_id
                       )
                       OR (
                           hops.direction IN (1, 3)
                           AND edge.dst = chain_walk.node_id
                       )
                       OR (
                           hops.direction = 1
                           AND edge.undirected
                           AND edge.src = chain_walk.node_id
                       )
                       OR (
                           hops.direction = 2
                           AND edge.undirected
                           AND edge.dst = chain_walk.node_id
                       )
                   )
                JOIN anchors tgt
                    ON tgt.id = CASE
                        WHEN edge.src = chain_walk.node_id THEN edge.dst
                        ELSE edge.src
                    END
                   AND tgt.kind = 'NodeAnchor'
                """;
    }
    sql = f"""
            WITH RECURSIVE
            specs(idx, from_type, is_visit, chain_len) AS (
                VALUES
                    {spec_values_sql}
            ),
            hops(spec_idx, hop_idx, edge_type, node_type, direction) AS (
                VALUES
                    {hop_values_sql}
            ),
            frontier(node_id, frontier_ord) AS (
                SELECT seed.id, seed.ord
                FROM unnest(CAST(:frontier_ids AS uuid[]))
                    WITH ORDINALITY AS seed(id, ord)
                JOIN anchors n ON n.id = seed.id
                 AND n.kind = 'NodeAnchor'
            ),
            chain_walk(
                spec_idx,
                chain_len,
                is_visit,
                seed_ord,
                hop_idx,
                node_id,
                path_nodes,
                hop_ord
            ) AS (
                SELECT
                    specs.idx AS spec_idx,
                    specs.chain_len AS chain_len,
                    specs.is_visit AS is_visit,
                    frontier.frontier_ord AS seed_ord,
                    0 AS hop_idx,
                    frontier.node_id AS node_id,
                    ARRAY[frontier.node_id]::uuid[] AS path_nodes,
                    ARRAY[]::bigint[] AS hop_ord
                FROM frontier
                JOIN anchors cur
                    ON cur.id = frontier.node_id
                   AND cur.kind = 'NodeAnchor'
                JOIN specs ON specs.chain_len > 0
                 AND (
                     specs.from_type IS NULL
                     OR cur.arch_type = specs.from_type
                     OR EXISTS (
                         SELECT 1 FROM graph_types gt
                         WHERE gt.type_name = cur.arch_type
                           AND gt.ancestor = specs.from_type
                     )
                 )
                UNION ALL
                SELECT
                    chain_walk.spec_idx,
                    chain_walk.chain_len,
                    chain_walk.is_visit,
                    chain_walk.seed_ord,
                    hops.hop_idx + 1,
                    tgt.id AS node_id,
                    chain_walk.path_nodes || tgt.id,
                    chain_walk.hop_ord
                        || CAST(COALESCE(edge.seq, 0) AS bigint)
                FROM chain_walk
                JOIN hops
                    ON hops.spec_idx = chain_walk.spec_idx
                   AND hops.hop_idx = chain_walk.hop_idx
                {edge_step_sql}
                WHERE chain_walk.hop_idx < chain_walk.chain_len
                  AND (
                      hops.edge_type IS NULL
                      OR edge.arch_type = hops.edge_type
                      OR EXISTS (
                          SELECT 1 FROM graph_types gt
                          WHERE gt.type_name = edge.arch_type
                            AND gt.ancestor = hops.edge_type
                      )
                  )
                  AND (
                      hops.node_type IS NULL
                      OR tgt.arch_type = hops.node_type
                      OR EXISTS (
                          SELECT 1 FROM graph_types gt
                          WHERE gt.type_name = tgt.arch_type
                            AND gt.ancestor = hops.node_type
                      )
                  )
                  AND NOT (tgt.id = ANY(chain_walk.path_nodes))
            ),
            candidate_node_rows AS (
                SELECT
                    0::int AS phase,
                    frontier.frontier_ord::bigint AS seed_ord,
                    -1::int AS spec_idx,
                    ARRAY[]::bigint[] AS hop_ord,
                    frontier.node_id AS target_id,
                    FALSE AS is_frontier
                FROM frontier
                UNION ALL
                SELECT
                    1::int AS phase,
                    chain_walk.seed_ord,
                    chain_walk.spec_idx,
                    chain_walk.hop_ord,
                    chain_walk.node_id AS target_id,
                    chain_walk.is_visit AS is_frontier
                FROM chain_walk
                WHERE chain_walk.hop_idx = chain_walk.chain_len
            ),
            node_rows AS (
                SELECT
                    candidate_node_rows.phase,
                    candidate_node_rows.seed_ord,
                    candidate_node_rows.spec_idx,
                    candidate_node_rows.hop_ord,
                    candidate_node_rows.target_id,
                    candidate_node_rows.is_frontier,
                    CASE
                        WHEN n.kind = 'NodeAnchor' AND n.arch_type = 'Root'
                            THEN n.id
                        ELSE n.root_id
                    END AS owner_root
                FROM candidate_node_rows
                JOIN anchors n ON n.id = candidate_node_rows.target_id
                 AND n.kind = 'NodeAnchor'
            ),
            raw_additions AS (
                SELECT
                    phase,
                    seed_ord,
                    spec_idx,
                    hop_ord,
                    0 AS sub_ord,
                    target_id AS id,
                    is_frontier
                FROM node_rows
                UNION ALL
                SELECT
                    phase,
                    seed_ord,
                    spec_idx,
                    hop_ord,
                    1 AS sub_ord,
                    owner_root AS id,
                    FALSE AS is_frontier
                FROM node_rows
                WHERE owner_root IS NOT NULL
                  AND CAST(:include_owner_roots AS boolean)
                  AND owner_root <> target_id
            ),
            filtered_additions AS (
                SELECT *
                FROM raw_additions
                WHERE id IS NOT NULL
                  AND (
                      CAST(:seen_count AS int) = 0
                      OR NOT (id = ANY(CAST(:seen_ids AS uuid[])))
                  )
            ),
            dedup_additions AS (
                SELECT DISTINCT ON (id)
                    id,
                    phase,
                    seed_ord,
                    spec_idx,
                    hop_ord,
                    sub_ord,
                    is_frontier
                FROM filtered_additions
                ORDER BY id, phase, seed_ord, spec_idx, hop_ord, sub_ord
            ),
            ordered_plan AS (
                SELECT
                    id,
                    is_frontier,
                    ROW_NUMBER() OVER (
                        ORDER BY phase, seed_ord, spec_idx, hop_ord, sub_ord, id
                    ) AS ord
                FROM dedup_additions
            ),
            prefetch_plan AS (
                SELECT id, is_frontier, ord
                FROM ordered_plan
                WHERE ord <= CAST(:limit AS bigint)
            ),
            plan_rows AS (
                SELECT
                    p.ord,
                    p.id,
                    n.arch_type,
                    CASE
                        WHEN n.kind = 'NodeAnchor' AND n.arch_type = 'Root'
                            THEN n.id
                        ELSE n.root_id
                    END AS owner_root,
                    COALESCE(string_agg(DISTINCT gt.ancestor, ','), n.arch_type)
                        AS ancestors,
                    p.is_frontier
                FROM prefetch_plan p
                JOIN anchors n ON n.id = p.id
                 AND n.kind = 'NodeAnchor'
                LEFT JOIN graph_types gt ON gt.type_name = n.arch_type
                GROUP BY
                    p.ord,
                    p.id,
                    p.is_frontier,
                    n.id,
                    n.kind,
                    n.arch_type,
                    n.root_id
            )
            SELECT
                ord,
                id,
                arch_type,
                owner_root,
                ancestors,
                is_frontier
            FROM plan_rows
            ORDER BY ord
            """;
    return (sql,base_params);
}
