"""Transformer architecture built exclusively from reusable runtime primitives."""
import torch;
import math;
import initialization;
import from jaclang.lib.tensor_graph.runtime {
    TensorGraph, Input, Parameter, Constant, MatMul, Add, Multiply, Subtract,
    Square, Rsqrt, ReduceMean, ReLU, Reshape, Transpose, Contiguous,
    Softmax, Gather, MaskedFill, Arange, Full, Triu
}
# These helpers build nodes/edges and initialize parameters; they never run forward computations.
def linear(m: TensorGraph, prefix: str, x: str, din: int, dout: int, rng: any) -> str {
    w = m.add(Parameter(name=prefix + ".weight", value=initialization.weight([din, dout], rng)));
    b = m.add(Parameter(name=prefix + ".bias", value=initialization.zeros([dout])));
    mm = m.add(MatMul(name=prefix + ".matmul"), {"a": x, "b": w});
    return m.add(Add(name=prefix), {"a": mm, "b": b});
}
def attention(m: TensorGraph, prefix: str, x: str, memory: str, d: int, h: int, rng: any, causal: bool = False) -> str {
    width = d // h;
    heads: dict[str, str] = {};
    for (letter, producer) in [("q", x), ("k", memory), ("v", memory)] {
        proj = linear(m, prefix + "." + letter, producer, d, d, rng);
        reshaped = m.add(Reshape(name=prefix + "." + letter + ".reshape", dimensions=[-1, h, width]), {"x": proj});
        heads[letter] = m.add(Transpose(name=prefix + "." + letter + ".heads"), {"x": reshaped});
    }
    kt = m.add(Transpose(name=prefix + ".k.transpose", dim0=-2, dim1=-1), {"x": heads["k"]});
    score = m.add(MatMul(name=prefix + ".score.matmul"), {"a": heads["q"], "b": kt});
    scale = m.add(Constant(name=prefix + ".scale", value=initialization.scalar(1 / math.sqrt(width))));
    score = m.add(Multiply(name=prefix + ".score"), {"a": score, "b": scale});
    if causal {
        full = m.add(Full(name=prefix + ".mask.full"), {"ref": "target"});
        mask = m.add(Triu(name=prefix + ".mask"), {"x": full});
        score = m.add(MaskedFill(name=prefix + ".masked"), {"x": score, "mask": mask});
    }
    probs = m.add(Softmax(name=prefix + ".probabilities"), {"x": score});
    context = m.add(MatMul(name=prefix + ".context"), {"a": probs, "b": heads["v"]});
    trans = m.add(Transpose(name=prefix + ".context.transpose"), {"x": context});
    contig = m.add(Contiguous(name=prefix + ".context.contiguous"), {"x": trans});
    joined = m.add(Reshape(name=prefix + ".joined", dimensions=[-1, d]), {"x": contig});
    return linear(m, prefix + ".output", joined, d, d, rng);
}
def norm(m: TensorGraph, prefix: str, main: str, residual_source: str, d: int) -> str {
    added = m.add(Add(name=prefix + ".residual"), {"a": main, "b": residual_source});
    mean = m.add(ReduceMean(name=prefix + ".mean"), {"x": added});
    center = m.add(Subtract(name=prefix + ".center"), {"a": added, "b": mean});
    square = m.add(Square(name=prefix + ".square"), {"x": center});
    variance = m.add(ReduceMean(name=prefix + ".variance"), {"x": square});
    epsilon = m.add(Constant(name=prefix + ".epsilon", value=initialization.scalar(1e-5)));
    stable = m.add(Add(name=prefix + ".stable"), {"a": variance, "b": epsilon});
    inv = m.add(Rsqrt(name=prefix + ".rsqrt"), {"x": stable});
    normalized = m.add(Multiply(name=prefix + ".normalized"), {"a": center, "b": inv});
    gamma = m.add(Parameter(name=prefix + ".gamma", value=initialization.ones([d])));
    beta = m.add(Parameter(name=prefix + ".beta", value=initialization.zeros([d])));
    scaled = m.add(Multiply(name=prefix + ".scaled"), {"a": normalized, "b": gamma});
    return m.add(Add(name=prefix), {"a": scaled, "b": beta});
}
def feed_forward(m: TensorGraph, prefix: str, x: str, d: int, hidden: int, rng: any) -> str {
    up = linear(m, prefix + ".up", x, d, hidden, rng);
    activated = m.add(ReLU(name=prefix + ".relu"), {"x": up});
    return linear(m, prefix + ".output", activated, hidden, d, rng);
}
def embedding(m: TensorGraph, prefix: str, token: str, d: int, v: int, rng: any) -> str {
    table = m.add(Parameter(name=prefix + ".table", value=initialization.weight([v, d], rng)));
    gather = m.add(Gather(name=prefix + ".gather"), {"table": table, "indices": token});
    return m.add(Multiply(name=prefix), {"a": gather, "b": "embedding_scale"});
}
def build(dimension: int = 8, heads: int = 2, hidden: int = 16, vocabulary: int = 13, capacity: int = 256) -> TensorGraph {
    assert dimension > 0 and heads >= 2 and dimension % heads == 0;
    assert hidden > 0 and vocabulary > 2 and capacity > 0;
    m = TensorGraph(output_name="probabilities");
    rng = torch.Generator().manual_seed(1729);
    m.add(Input(name="source")); m.add(Input(name="target"));
    m.add(Constant(name="embedding_scale", value=initialization.scalar(math.sqrt(dimension))));
    m.add(Constant(name="position_table", value=initialization.position_table(capacity, dimension)));
    ep = embedding(m, "enc_embed", "source", dimension, vocabulary, rng);
    dp = embedding(m, "dec_embed", "target", dimension, vocabulary, rng);
    for (prefix, token, embed) in [("enc_pos", "source", ep), ("dec_pos", "target", dp)] {
        indices = m.add(Arange(name=prefix + ".indices"), {"ref": token});
        positions = m.add(Gather(name=prefix + ".positions"), {"table": "position_table", "indices": indices});
        m.add(Add(name=prefix), {"a": embed, "b": positions});
    }
    ea = attention(m, "enc_attn", "enc_pos", "enc_pos", dimension, heads, rng);
    en1 = norm(m, "enc_norm1", ea, "enc_pos", dimension);
    ef = feed_forward(m, "enc_ffn", en1, dimension, hidden, rng);
    memory = norm(m, "enc_norm2", ef, en1, dimension);
    da = attention(m, "dec_attn", "dec_pos", "dec_pos", dimension, heads, rng, True);
    dn1 = norm(m, "dec_norm1", da, "dec_pos", dimension);
    cross = attention(m, "cross_attn", dn1, memory, dimension, heads, rng);
    dn2 = norm(m, "dec_norm2", cross, dn1, dimension);
    df = feed_forward(m, "dec_ffn", dn2, dimension, hidden, rng);
    dn3 = norm(m, "dec_norm3", df, dn2, dimension);
    logits = linear(m, "projection", dn3, dimension, vocabulary, rng);
    m.add(Softmax(name="probabilities"), {"x": logits});
    return m;
}
