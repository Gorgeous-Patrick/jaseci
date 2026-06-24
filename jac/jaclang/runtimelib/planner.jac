"""Query planner — picks the execution strategy for a QueryPlan.

The planner is the only place that knows about all three layers:

  1. Backend native pushdown (`Memory.execute_plan`, declared via
     `Memory.capabilities()`). Fastest when the backend can handle the plan
     because it bypasses the topology_index entirely.
  2. Root topology_index (`TopologyIndex.resolve_chain[_ordered]`). The
     universal in-process narrowing path. Always available when the index is
     enabled and the relevant root carries one.
  3. `batch_get` (every backend has this). The bulk-load primitive used after
     narrowing to materialize anchors → archetypes.

Strategy selection:

  * `pushdown`  — `plan.needs() <= backend.capabilities()`. Hand the whole
                  plan to the backend; iterate its generator.
  * `mixed`     — topology_index resolves the chain to a candidate UUID set,
                  the planner attaches that set as `plan.id_in`, and the
                  reduced plan (now needing `id_in` + maybe `field_pushdown`)
                  goes to the backend if it covers those needs. Otherwise the
                  planner falls through to `floor`.
  * `floor`     — topology_index → `batch_get`. Pure in-process. Always
                  works as long as the index is populated.

The planner is also the one place that observes `JAC_QUERY_TRACE` to log
which strategy fired for which plan — invaluable when debugging unexpected
fallbacks or perf cliffs in CI.
"""

import os;
import inspect;
import dis;
import logging;
import from collections.abc { Generator }
import from functools { lru_cache }
import from uuid { UUID }

import from jaclang.jac0core.archetype { Anchor, Archetype, NodeAnchor }
import from jaclang.runtimelib.query_plan { QueryPlan }

glob logger = logging.getLogger(__name__),
     __all__ = ['execute_plan', 'execute_path', 'plan_chain', 'plan_chain_ordered'];


"""Hashable carrier so `lru_cache` can key on a function's `__code__` plus
the *type-valued* captures in its closure, while still passing the function
itself through to the cached implementation for `inspect.getclosurevars`.

Naively keying on `__code__` alone is incorrect under a shared-helper
codegen pattern such as:

    def mk_filter(arch): return lambda x: isinstance(x, arch);
    f_a = mk_filter(TypeA);
    f_b = mk_filter(TypeB);

Both `f_a` and `f_b` would share `__code__` but capture *different*
archetype classes; a code-only cache would silently return the first
result for every subsequent call. Today's Jac codegen doesn't emit that
pattern, but nothing in the planner enforces it.

Including the closure's type-valued contents (Archetype subclasses are
always classes, so we only need to capture `type` cells) makes the key
faithful to the computation: the cache only hits when both the bytecode
and the captured class set match. The closure walk to extract those cells
is a constant-time touch of `filt.__closure__`, not the expensive
`inspect.getclosurevars` walk."""
class _CodeKey {
    has filt: any,
        code: any,
        closure_types: tuple;

    def init(self: _CodeKey, filt: any) {
        self.filt = filt;
        self.code = filt.__code__;
        cells = filt.__closure__ if filt.__closure__ is not None else ();
        self.closure_types = tuple(
            c.cell_contents
            for c in cells
            if isinstance(c.cell_contents, `type)
        );
    }

    def __hash__(self: _CodeKey) -> int {
        return hash((self.code, self.closure_types));
    }

    def __eq__(self: _CodeKey, other: object) -> bool {
        return (
            isinstance(other, _CodeKey)
            and self.code is other.code
            and self.closure_types == other.closure_types
        );
    }
}


"""Cached impl keyed by a `_CodeKey` wrapper whose hash is the function's
`__code__`. Two lambdas with the same source compile to the same code
object, so any number of fresh function instances at the same call site
collapse to one cache entry."""
@lru_cache(maxsize=None)
def _filter_type_name_by_code(key: _CodeKey) -> (str | None) {
    try {
        closure = inspect.getclosurevars(key.filt);
        for val in `list(closure.nonlocals.values()) + `list(
            closure.globals.values()
        ) {
            if isinstance(val, `type) and issubclass(val, Archetype) {
                return val.__name__;
            }
        }
    } except Exception {
        ;
    }
    return None;
}


"""Inspect a Jac-emitted filter lambda for archetype-type identity.

Returns the archetype class name if the lambda is a pure `isinstance(i, T)`
check (or an Archetype instance acting as an identity filter). Returns None
when the filter is None or non-trivial.

Memoized by `filt.__code__` via `_CodeKey`. Jac emits filter lambdas inline
at the path-construction call site, so two walker spawns produce two
distinct function objects that share the same code — keying on identity
would never hit; keying on the code does."""
def _filter_type_name(filt: any) -> (str | None) {
    if filt is None {
        return None;
    }
    try {
        if isinstance(filt, Archetype) {
            return `type(filt).__name__;
        }
    } except Exception {
        ;
    }
    code = filt?.__code__;
    if code is None {
        return None;
    }
    return _filter_type_name_by_code(_CodeKey(filt));
}


"""Cached impl keyed on the bytecode object directly. `dis.get_instructions`
accepts a code object, so no function-object juggling needed here."""
@lru_cache(maxsize=None)
def _filter_has_predicates_by_code(code: any) -> bool {
    try {
        opcodes = {instr.opname for instr in dis.get_instructions(code)};
    } except (TypeError, AttributeError, ValueError) {
        return True;
    }
    return bool(opcodes & {'LOAD_ATTR', 'COMPARE_OP', 'CONTAINS_OP', 'IS_OP'});
}


"""Detect whether a filter lambda contains predicate ops beyond type checks.

Pure `isinstance(i, T)` checks compile to LOAD_GLOBAL + CALL_FUNCTION +
RETURN; predicates introduce LOAD_ATTR / COMPARE_OP / CONTAINS_OP / IS_OP.
Conservative on inspection failure — assume predicates present so we never
silently skip filtering.

Memoized by `filt.__code__`; see `_filter_type_name` for the why."""
def _filter_has_predicates(filt: any) -> bool {
    if filt is None {
        return False;
    }
    code = filt?.__code__;
    if code is None {
        # Non-function callable (rare); run uncached.
        try {
            opcodes = {instr.opname for instr in dis.get_instructions(filt)};
        } except (TypeError, AttributeError, ValueError) {
            return True;
        }
        return bool(opcodes & {'LOAD_ATTR', 'COMPARE_OP', 'CONTAINS_OP', 'IS_OP'});
    }
    return _filter_has_predicates_by_code(code);
}


"""Top-level entry point: execute a QueryPlan against a memory.

Returns an iterable of NodeAnchor results. Applies `plan.post_filter` if set.
Trivial plans (no chain, no filters, no narrowing) return empty — callers
should use `Memory.query()` directly for unfiltered scans.

The signature deliberately accepts `any` for `mem` so the planner can be
called from the bootstrap-compiled runtime layer without a circular import on
the Memory type.
"""
def execute_plan(mem: any, plan: QueryPlan) -> list[any];


"""High-level entry point: execute an `ObjectSpatialPath` against a memory.

This is what the runtime's `refs()` calls. Builds the QueryPlan from the
path's destinations, walks the strategy ladder (pushdown / mixed / floor),
applies the final node filter post-narrowing, and returns the result as
NodeAnchors in canonical edge-walk order (single-hop) or arbitrary order
(multi-hop set narrowing).

Returns None to signal "no fast path applies" — the caller should fall back
to the legacy edge-walk via `edges_to_nodes`. This happens when:
  * the path has predicate filters the index can't express
  * the origin isn't persistent (no root → no topology_index)
  * the chain has no useful filter (full walk anyway)
  * topology_index is disabled and no backend pushdown applies
"""
def execute_path(
    mem: any, path: any, slc: (slice | None) = None
) -> (list[any] | None);


"""Resolve a chain on a given root's topology_index to a `set[UUID]`.

Used internally by `execute_path` (and available to callers that want the
candidate set without materializing anchors). Returns None when no fast
path applies (index disabled, root has no index, or origin not persistent)."""
def plan_chain(
    root_anchor: any,
    origin_ids: set[UUID],
    chain: list[tuple[(str | None), (str | None), int]]
) -> (set[UUID] | None);


"""Compatibility helper: resolve the final hop in canonical edge-insertion
order with `slc` applied. Returns None when no ordered fast path applies."""
def plan_chain_ordered(
    root_anchor: any,
    origin_ids: set[UUID],
    chain: list[tuple[(str | None), (str | None), int]],
    slc: slice
) -> (list[UUID] | None);
