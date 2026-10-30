# Replaceable prefetch admission

TTG establishes that a future visit is stable, path-determined and execution-preserved. An admission model then decides whether fetching its data is worthwhile. The correctness certificate, supported-query checks and node budget are enforced by the runtime before admission.

## Interface and replacement

`PrefetchDecisionModel.decide(PrefetchFeatures) -> PrefetchAdmission` is the required interface. `observe(PrefetchOutcome)` is an optional feedback method. These types live in `jaclang.runtime.ttg_prefetch_model`.

Models receive a versioned feature record and return an admission flag, a reason, and an optional estimated score in milliseconds. Register a factory with `register_prefetch_model(name, factory)` and select it through the run configuration:

```toml
[run]
prefetching = "ttg_dependency"
async_prefetch = "thread"
ttg_prefetch_model = "expected_benefit"
```

The default model name is `always`, preserving the existing selective-prefetch baseline. `expected_benefit` selects the initial cost heuristic. A custom model can also be passed directly to `dependency_prefetch(ctx, model=my_model, provider=my_profile)` or installed for a scope with `use_prefetch_model(my_model)`. Scoped selection takes precedence over the configuration; direct injection takes precedence over scoped selection.

A replacement can implement just one method:

```jac
import from jaclang.runtime.ttg_prefetch_model {
    PrefetchDecisionModel, PrefetchFeatures, PrefetchAdmission
}

obj MyAdmissionModel(PrefetchDecisionModel) {
    def decide(features: PrefetchFeatures) -> PrefetchAdmission {
        return PrefetchAdmission(features.remaining_budget >= 4, 'minimum batch budget');
    }
}
```

Pass `MyAdmissionModel()` to `dependency_prefetch`; the surrounding runtime and feature provider stay the same.

The feature provider has a separate interface: `estimate(context) -> PrefetchFeatures`, with optional `observe`, `record_entry`, and `record_visit` methods. This allows replacing both the predictor and its measurement source independently. A fresh `OnlinePrefetchProfile()` provides isolated measurements for an experiment. The default provider keeps bounded, process-local statistics keyed by program-plan hash, ability, visit event, execution mode and worker count.

## Runtime sequence

1. A compiler-inserted checkpoint establishes the safety certificate for a queued target.
2. Before issuing the target-resolution SQL, the runtime asks the model about the `resolve` phase. Rejection avoids that SQL and leaves fetching to normal execution.
3. After resolution, the runtime asks about the `load` phase with the actual target count. Rejection leaves the already resolved data unloaded.
4. An admitted load uses the existing prefetch dispatcher and raw cache.
5. Actual ability entry and pre-visit hooks record executed branches and demand timestamps. Worker completion records payload readiness after cache publication.
6. At scope exit, workers are joined and outcomes are sent to the provider and model.

Each proposed plan logs both decisions, feature snapshots, reasons and decision time. Model/provider exceptions skip the speculative operation and appear in the run's error list. Tests exercise both rejection stages and foreground results.

## Initial expected-benefit model

Let `p` be the probability that a certified opportunity is actually demanded, `L` the measured payload-ready latency, `W` the available overlap window, and `R` the target-resolution latency. The initial score is:

```text
score = p * min(L, W) - resolution_cost - (1-p) * L * unused_weight - margin
resolution_cost = R in resolve phase; 0 in load phase
admit when score > 0
```

The second phase treats resolution cost as already incurred. The model exposes minimum sample count, margin, unused-load weight, cold-start admission and probe interval as constructor parameters. It initially admits measurement probes until three samples exist and periodically probes every twenty opportunities. Synchronous loading has no overlap and is rejected by this heuristic.

`branch_frequency` counts actual executions of a visit divided by entries to its containing ability. `use_probability` estimates actual demand among already certified opportunities, using `(demanded + 1) / (opportunities + 2)`. A branch known to be selected at a checkpoint must not be discounted again by its marginal execution frequency. The initial heuristic therefore reports branch frequency as a feature while using conditional demand probability for admission.

## Measurement boundaries

The default provider averages resolution, payload-ready and overlap observations separately. Missing measurements remain absent. Resolution time covers SQL construction, savepoint-protected lookup and ID processing. Payload-ready latency runs from dispatch to worker completion; with multiple workers it uses the final completion. Demand is timestamped before the ordinary visit evaluates its graph query, so payload waiting does not inflate the overlap estimate. Decision time is logged separately.

These are runtime costs relevant to admission, rather than database-only RTT measurements. The heuristic is an initial policy for experimentation. Its score uses mean costs, and workload contention, cache changes and target-size variation can affect predictions. Compare it with `always` and disabled prefetch using fresh or explicitly warmed profiles, and report measured outcomes.
