"""Replaceable admission policies and independent measurement aggregation."""
import from jaclang.runtime.ttg_prefetch_model {
    PrefetchFeatures,
    PrefetchAdmission,
    PrefetchOutcome,
    PrefetchDecisionModel,
    ExpectedBenefit,
    AlwaysPrefetch,
    register_prefetch_model,
    unregister_prefetch_model,
    create_prefetch_model,
    use_prefetch_model,
    _model_override
}
import from jaclang.runtime.ttg_prefetch_profile { OnlinePrefetchProfile }

obj RejectPrefetch(PrefetchDecisionModel) {
    def decide(features: PrefetchFeatures) -> PrefetchAdmission {
        return PrefetchAdmission(False, 'test rejection');
    }
}

def measured_features -> PrefetchFeatures {
    return PrefetchFeatures(
        site_key='site',
        ability_key='ability',
        phase='resolve',
        queue_position=0,
        remaining_budget=20,
        mode='thread',
        estimated_nodes=3.0,
        use_probability=1.0,
        overlap_ms=8.0,
        resolution_ms=2.0,
        payload_ms=10.0,
        samples=4,
        opportunities=4
    );
}

test "prefetch model: measured benefit and sunk resolution cost" {
    model = ExpectedBenefit();
    features = measured_features();
    result = model.decide(features);
    assert result.admit and result.score_ms == 6.0;
    features.resolution_ms = 12.0;
    assert not model.decide(features).admit;
    features.phase = 'load';
    assert model.decide(features).score_ms == 8.0;
    features.use_probability = 0.1;
    assert not model.decide(features).admit;
}

test "prefetch model: conditional use differs from marginal branch frequency" {
    model = ExpectedBenefit();
    features = measured_features();
    features.branch_frequency = 0.01;
    first = model.decide(features);
    features.branch_frequency = 1.0;
    second = model.decide(features);
    assert first.to_dict() == second.to_dict();
}

test "prefetch model: cold starts, periodic probes, sync and invalid estimates" {
    model = ExpectedBenefit();
    features = measured_features();
    features.samples = 0;
    result = model.decide(features);
    assert result.admit and result.probe;
    assert not ExpectedBenefit(cold_start_prefetch=False).decide(features).admit;
    features.samples = 4;
    features.resolution_ms = 100.0;
    features.opportunities = 19;
    assert model.decide(features).probe;
    features.opportunities = 4;
    assert not model.decide(features).admit;
    features.resolution_ms = float('nan');
    assert model.decide(features).reason == 'invalid measurement values';
    features.mode = '';
    assert not model.decide(features).admit;
    features.mode = 'thread';
    features.estimated_nodes = 0.0;
    assert model.decide(features).reason == 'observed target sets are empty';
}

test "prefetch profile: actual counters and measured costs stay independent" {
    profile = OnlinePrefetchProfile();
    profile.record_entry('ability');
    profile.record_entry('ability');
    profile.record_visit('ability', 'site');
    profile.observe(PrefetchOutcome('site', 'ability', True, 2.0, 10.0, 8.0, 3));
    profile.observe(PrefetchOutcome('site', 'ability', False, 4.0, None, None, 0));
    features = profile.estimate(measured_features());
    assert features.branch_frequency == 0.5;
    assert features.use_probability == 0.5;
    assert features.resolution_ms == 3.0;
    assert features.payload_ms == 10.0;
    assert features.overlap_ms == 8.0;
    assert features.estimated_nodes == 1.5;
    assert features.samples == 1;
    fresh = OnlinePrefetchProfile();
    assert fresh.estimate(
        PrefetchFeatures('site', 'ability', 'resolve', 0, 20, 'thread')
    ).opportunities
        == 0;
    profile.clear();
    assert len(profile.sites) == 0;
}

test "prefetch model: registered factories and scoped replacement" {
    register_prefetch_model('unit_reject', RejectPrefetch);
    try {
        custom = create_prefetch_model('unit_reject');
        assert isinstance(custom, RejectPrefetch);
        assert not custom.decide(measured_features()).admit;
        previous = _model_override.get();
        with use_prefetch_model(custom) {
            assert _model_override.get() is custom;
            with use_prefetch_model(AlwaysPrefetch()) {
                assert isinstance(_model_override.get(), AlwaysPrefetch);
            }
            assert _model_override.get() is custom;
        }
        assert _model_override.get() is previous;
    } finally {
        unregister_prefetch_model('unit_reject');
    }
}
