"""No-op prefetch prediction policy."""

import from jaclang.jac0core.prefetch_policy_types {
    PrefetchPlanRequest,
    PrefetchPlanResult
}

def none_policy_plan(request: PrefetchPlanRequest) -> PrefetchPlanResult {
    return PrefetchPlanResult(ids=[]);
}
