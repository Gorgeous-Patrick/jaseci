"""Executable assertions; intentionally scoped to this example."""
import from model { build, greedy, Flow, Model, Input, Embedding, PositionalEncoding, SelfAttention, CausalSelfAttention, CrossAttention, FeedForward, AddNorm, Linear, Softmax, D, VOCAB }
import math_cpu;
import reference;
import copy;

def verify_reference(m: Model, source: list[int], target: list[int]) -> float {
    result = m.forward(source, target);
    expected = reference.forward(m.parameter_snapshot(), source, target);
    errors: list[float] = [];
    for (name, n) in m.modules.items() {
        errors.append(math_cpu.max_error(n.output, expected[name]));
        if not isinstance(n, Input) {
            rows = len(source) if name.startswith("enc_") else len(target);
            columns = VOCAB if isinstance(n, (Linear, Softmax)) else D;
            math_cpu.check_matrix(n.output, rows, columns);
        }
    }
    math_cpu.check_probs(result.probabilities, len(target), VOCAB);
    assert max(errors) < 1e-12;
    return max(errors);
}

with entry {
    m = build();
    assert type(m.modules["source"]) is Input;
    assert type(m.modules["enc_embed"]) is Embedding;
    assert type(m.modules["enc_pos"]) is PositionalEncoding;
    assert type(m.modules["enc_attn"]) is SelfAttention;
    assert type(m.modules["dec_attn"]) is CausalSelfAttention;
    assert type(m.modules["cross_attn"]) is CrossAttention;
    assert type(m.modules["enc_ffn"]) is FeedForward;
    assert type(m.modules["enc_norm1"]) is AddNorm;
    assert type(m.modules["projection"]) is Linear;
    assert type(m.modules["probabilities"]) is Softmax;
    for n in m.modules.values() {
        assert not hasattr(n, "kind") and not hasattr(n, "weights");
        if isinstance(n, (Input, PositionalEncoding, Softmax)) { assert n.parameters() == {}; }
    }
    source = [3, 4, 5, 2];
    target = [1, 6, 7];
    run = m.forward(source, target);
    baseline = copy.deepcopy(run.probabilities);
    params = m.parameter_snapshot();
    embed = m.modules["enc_embed"];
    assert isinstance(embed, Embedding);
    assert params["enc_embed"]["table"] is not embed.table;
    assert m.modules["enc_attn"].parameters()["w_q"] is not m.modules["cross_attn"].parameters()["w_q"];
    expected = reference.forward(params, source, target);
    errors = [math_cpu.max_error(n.output, expected[name]) for (name, n) in m.modules.items()];
    assert max(errors) < 1e-12;
    math_cpu.check_probs(baseline, 3, VOCAB);
    assert len(run.trace) == 18 and len(set(run.trace)) == 18;
    assert len(run.deliveries) == 22;
    for (name, n) in m.modules.items() {
        assert set(n.inbox) == set(n.required);
        for e in [edge n->:Flow:->] {
            dest = e.__jac__.target.archetype;
            assert run.trace.index(name) < run.trace.index(dest.name);
            assert dest.inbox[e.role] is n.output;
        }
    }
    for name in ["enc_norm1", "enc_norm2", "dec_norm1", "dec_norm2", "dec_norm3"] {
        assert set(m.modules[name].inbox) == {"main", "skip"};
        assert m.modules[name].inbox["main"] is not m.modules[name].inbox["skip"];
    }
    maps = m.modules["dec_attn"].diagnostics["attention"];
    assert len(maps) == 2;
    for name in ["enc_attn", "dec_attn", "cross_attn"] {
        attn_maps = m.modules[name].diagnostics["attention"];
        assert len(attn_maps) == 2;
        rows = len(source) if name == "enc_attn" else len(target);
        columns = len(target) if name == "dec_attn" else len(source);
        for head in attn_maps { math_cpu.check_probs(head, rows, columns); }
    }
    for head in maps {
        for (t, row) in enumerate(head) {
            assert abs(sum(row) - 1) < 1e-12;
            assert all([v == 0.0 for v in row[t + 1:]]);
        }
    }
    # Future-token perturbation cannot change earlier decoder outputs.
    changed = m.forward(source, [1, 6, 10]);
    assert math_cpu.max_error(baseline[:2], changed.probabilities[:2]) < 1e-12;
    assert math_cpu.max_error(baseline[2], changed.probabilities[2]) > 1e-6;
    # Source changes must reach the output via the memory edge.
    influenced = m.forward([8, 9, 10, 2], target);
    influence = math_cpu.max_error(baseline, influenced.probabilities);
    assert influence > 1e-6;
    assert m.modules["cross_attn"].inbox["memory"] is m.modules["enc_norm2"].output;
    # Different lengths followed by the original input prove reset/state isolation.
    length_errors = [verify_reference(m, [8, 2], [1]),
                     verify_reference(m, [3], [1, 4, 5, 6, 7]),
                     verify_reference(m, [3, 4, 5, 6, 2], [1, 8])];
    repeated = m.forward(source, target);
    assert math_cpu.max_error(baseline, repeated.probabilities) == 0;
    assert repeated.trace == run.trace and repeated.deliveries == run.deliveries;
    assert baseline == run.probabilities;
    # Reverse the real entry-edge order: dependency joins remain correct.
    del [edge m->:Flow:->];
    m +>: Flow(role="entry", path="seed") :+> m.modules["target"];
    m +>: Flow(role="entry", path="seed") :+> m.modules["source"];
    reordered = m.forward(source, target);
    assert reordered.trace[0] == "target";
    assert math_cpu.max_error(baseline, reordered.probabilities) == 0;
    # Change a true graph residual edge: execution must follow the altered wiring.
    n = m.modules["enc_pos"];
    del [edge n->:Flow:role == "skip":->];
    m.wire("enc_attn", "enc_norm1", "skip", "residual");
    rewired = m.forward(source, target);
    rewired_skip = m.modules["enc_norm1"].inbox["skip"];
    assert rewired_skip is m.modules["enc_attn"].output;
    assert math_cpu.max_error(baseline, rewired.probabilities) > 1e-6;
    # Remove required encoder memory: no hidden pipeline can bypass the missing edge.
    memory_node = m.modules["enc_norm2"];
    del [edge memory_node->:Flow:->];
    blocked = False;
    try { m.forward(source, target); }
    except AssertionError { blocked = True; }
    assert blocked;
    assert m.modules["enc_norm2"].done;
    assert not m.modules["cross_attn"].done and not m.modules["probabilities"].done;
    assert "x" in m.modules["cross_attn"].inbox and "memory" not in m.modules["cross_attn"].inbox;
    # Node parameters are the actual parameters, including norm affine/bias.
    m = build();
    norm = m.modules["dec_norm3"];
    projection = m.modules["projection"];
    assert isinstance(norm, AddNorm) and isinstance(projection, Linear);
    norm.gamma[0] = 1.7;
    norm.beta[1] = 0.3;
    projection.bias[4] = 0.2;
    projection.weight[0][4] += 0.1;
    embed = m.modules["enc_embed"];
    ff = m.modules["dec_ffn"];
    assert isinstance(embed, Embedding) and isinstance(ff, FeedForward);
    embed.table[3][0] += 0.4;
    ff.w_up[0][0] += 0.2;
    ff.b_up[0] = 0.1;
    ff.w_down[0][0] += 0.3;
    ff.b_down[1] = 0.2;
    for name in ["enc_attn", "dec_attn", "cross_attn"] {
        attn = m.modules[name];
        assert isinstance(attn, (SelfAttention, CausalSelfAttention, CrossAttention));
        attn.w_q[0][0] += 0.1;
        attn.b_q[0] = 0.2;
        attn.w_k[1][0] += 0.2;
        attn.b_k[1] = 0.1;
        attn.w_v[0][1] += 0.3;
        attn.b_v[0] = 0.2;
        attn.w_o[1][0] += 0.1;
        attn.b_o[1] = 0.3;
    }
    mutation_error = verify_reference(m, source, target);
    assert math_cpu.max_error(baseline, m.modules["probabilities"].output) > 1e-6;
    generated = greedy(m, source, steps=4);
    assert generated[0] == 1 and 2 <= len(generated) <= 5;
    print("PASS: independent reference across all 18 nodes; max error:", max(errors));
    print("PASS: ten concrete node types, named parameter fields, independent snapshot");
    print("PASS: all intermediate shapes/finite across source/target lengths 2/1, 1/5, 5/2; max error:", max(length_errors));
    print("PASS: shape/finite/normalized, 2-head causal mask and future-token isolation");
    print("PASS: encoder influence through cross-attention; max probability delta:", influence);
    print("PASS: reset, trace, all 22 role deliveries, five residual joins");
    print("PASS: reversed input traversal order preserves dependency joins");
    print("PASS: rewired residual changes inference; deleted memory blocks inference");
    print("PASS: embedding, Q/K/V/O, FFN, norm and Linear field mutations; max error:", mutation_error);
    print("PASS: greedy generation:", generated);
}
