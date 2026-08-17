"""TTG-backed prefetch prediction policy."""

import from jaclang.jac0core.prefetch_policy_types {
    PrefetchPlanRequest,
    PrefetchPlanResult
}

def ttg_policy_plan(request: PrefetchPlanRequest) -> PrefetchPlanResult {
    import time as _time;
    import from typing { cast }
    import from logging { getLogger as _getLogger }
    import from jaclang.jac0core.ttg { JacTTGGenerator }
    import from jaclang.runtimelib.topo_utils { _get_root_anchor }

    result = PrefetchPlanResult(ids=[]);
    if request.start_anchor is None or request.start_id is None {
        return result;
    }
    topo_idx_start = _time.perf_counter();
    root_anchor = _get_root_anchor(request.start_anchor);
    if root_anchor is None {
        return result;
    }
    topo_idx = root_anchor.get_topology_index();
    topo_idx_end = _time.perf_counter();
    result.topology_ms = (topo_idx_end - topo_idx_start) * 1000;
    _node_table = cast(list, topo_idx.node_table);
    _adj_list = cast(list, topo_idx.adj_list);
    _getLogger(__name__).info(
        f"[TTG-DEBUG] topology_index: nodes={len(_node_table)}, "
        f"edges={len(_adj_list)}, "
        f"topology_index_data={'present'
            if root_anchor.topology_index_data
            else 'None'}"
    );
    plan_start = _time.perf_counter();
    result.ids = JacTTGGenerator.get_ttg_prefetch_list(
        request.warch,
        request.start_id,
        topo_idx,
        mem=request.mem,
        max_length=request.max_length
    );
    result.plan_ms = (_time.perf_counter() - plan_start) * 1000;
    result.resolve_ms = float(getattr(JacTTGGenerator, "_last_resolve_ms", 0.0));
    return result;
}
