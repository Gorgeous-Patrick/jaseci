"""Operation-level Transformer graph. Runtime has no Transformer module dispatcher."""
import torch;
import math;
import json;
import numerics;

edge TensorEdge { has port: str; }
edge Seed {}

node Operation {
    has name: str, inbox: dict[str, any] = {}, specs: dict[str, any] = {},
        output: any = None, spec: dict[str, any] = {},
        done: bool = False, queued: bool = False;
    def ports -> list[str] { return []; }
    def attributes -> dict[str, any] { return {}; }
    def ready(values: dict[str, any]) -> bool { return all([p in values for p in self.ports()]); }
    def infer -> dict[str, any] { raise NotImplementedError("primitive infer required"); }
    def evaluate -> any { raise NotImplementedError("primitive evaluate required"); }
}
node Input(Operation) {
    has value: any = None, supplied_spec: dict[str, any] = {};
    override def infer -> dict[str, any] { return self.supplied_spec; }
    override def evaluate -> any { return self.value; }
}
node Parameter(Operation) {
    has value: any = None;
    override def attributes -> dict[str, any] { return numerics.metadata(self.value); }
    override def infer -> dict[str, any] { return numerics.metadata(self.value); }
    override def evaluate -> any { return self.value; }
}
node Constant(Operation) {
    has value: any = None;
    override def attributes -> dict[str, any] { return numerics.metadata(self.value); }
    override def infer -> dict[str, any] { return numerics.metadata(self.value); }
    override def evaluate -> any { return self.value; }
}
node Binary(Operation) {
    override def ports -> list[str] { return ["a", "b"]; }
    override def infer -> dict[str, any] { return numerics.binary(self.specs["a"], self.specs["b"]); }
}
node Add(Binary) { override def evaluate -> any { return self.inbox["a"] + self.inbox["b"]; } }
node Multiply(Binary) { override def evaluate -> any { return self.inbox["a"] * self.inbox["b"]; } }
node Subtract(Binary) { override def evaluate -> any { return self.inbox["a"] - self.inbox["b"]; } }
node MatMul(Binary) {
    override def infer -> dict[str, any] { return numerics.matmul(self.specs["a"], self.specs["b"]); }
    override def evaluate -> any { return torch.matmul(self.inbox["a"], self.inbox["b"]); }
}
node Unary(Operation) {
    override def ports -> list[str] { return ["x"]; }
    override def infer -> dict[str, any] { return numerics.floating(self.specs["x"]); }
}
node Square(Unary) { override def evaluate -> any { return self.inbox["x"].square(); } }
node Rsqrt(Unary) { override def evaluate -> any { return torch.rsqrt(self.inbox["x"]); } }
node ReLU(Unary) { override def evaluate -> any { return torch.relu(self.inbox["x"]); } }
node Contiguous(Unary) { override def evaluate -> any { return self.inbox["x"].contiguous(); } }
node Softmax(Unary) {
    has axis: int = -1;
    override def attributes -> dict[str, any] { return {"axis": self.axis}; }
    override def infer -> dict[str, any] {
        numerics.axis(self.specs["x"], self.axis);
        return numerics.floating(self.specs["x"]);
    }
    override def evaluate -> any { return torch.softmax(self.inbox["x"], dim=self.axis); }
}
node ReduceMean(Unary) {
    has axis: int = -1, keepdim: bool = True;
    override def attributes -> dict[str, any] { return {"axis": self.axis, "keepdim": self.keepdim}; }
    override def infer -> dict[str, any] { return numerics.mean(self.specs["x"], self.axis, self.keepdim); }
    override def evaluate -> any { return self.inbox["x"].mean(dim=self.axis, keepdim=self.keepdim); }
}
node Reshape(Unary) {
    has dimensions: list[int] = [];
    override def attributes -> dict[str, any] { return {"dimensions": self.dimensions}; }
    override def infer -> dict[str, any] { return numerics.reshape(self.specs["x"], self.dimensions); }
    override def evaluate -> any { return self.inbox["x"].reshape(tuple(self.dimensions)); }
}
node Transpose(Unary) {
    has dim0: int = 0, dim1: int = 1;
    override def attributes -> dict[str, any] { return {"dim0": self.dim0, "dim1": self.dim1}; }
    override def infer -> dict[str, any] { return numerics.transpose(self.specs["x"], self.dim0, self.dim1); }
    override def evaluate -> any { return self.inbox["x"].transpose(self.dim0, self.dim1); }
}
node Gather(Operation) {
    has axis: int = 0;
    override def ports -> list[str] { return ["table", "indices"]; }
    override def attributes -> dict[str, any] { return {"axis": self.axis}; }
    override def infer -> dict[str, any] { return numerics.gather(self.specs["table"], self.specs["indices"], self.axis); }
    override def evaluate -> any { return torch.index_select(self.inbox["table"], self.axis, self.inbox["indices"]); }
}
node MaskedFill(Operation) {
    has fill: float = -math.inf;
    override def ports -> list[str] { return ["x", "mask"]; }
    override def attributes -> dict[str, any] { return {"fill": str(self.fill)}; }
    override def infer -> dict[str, any] { return numerics.masked_fill(self.specs["x"], self.specs["mask"]); }
    override def evaluate -> any { return self.inbox["x"].masked_fill(self.inbox["mask"], self.fill); }
}
node Arange(Operation) {
    has axis: int = 0;
    override def ports -> list[str] { return ["ref"]; }
    override def attributes -> dict[str, any] { return {"axis": self.axis}; }
    override def infer -> dict[str, any] { return numerics.arange(self.specs["ref"], self.axis); }
    override def evaluate -> any {
        ref = self.inbox["ref"];
        return torch.arange(ref.shape[self.axis], device=ref.device, dtype=torch.int64);
    }
}
node Full(Operation) {
    has axes: list[int] = [0, 0], dtype: str = "bool", fill: int = 1;
    override def ports -> list[str] { return ["ref"]; }
    override def attributes -> dict[str, any] { return {"axes": self.axes, "dtype": self.dtype, "fill": self.fill}; }
    override def infer -> dict[str, any] { return numerics.full(self.specs["ref"], self.axes, self.dtype); }
    override def evaluate -> any {
        ref = self.inbox["ref"];
        return torch.full(tuple([ref.shape[i] for i in self.axes]), self.fill, device=ref.device, dtype=getattr(torch, self.dtype));
    }
}
node Triu(Unary) {
    has diagonal: int = 1;
    override def attributes -> dict[str, any] { return {"diagonal": self.diagonal}; }
    override def infer -> dict[str, any] { return numerics.triu(self.specs["x"]); }
    override def evaluate -> any { return self.inbox["x"].triu(self.diagonal); }
}

node Model {
    has ops: dict[str, Operation] = {}, analysis: any = None, plan: any = None,
        device: str = "cpu", precision: str = "float64", vocabulary: int = 13,
        capacity: int = 256, dimension: int = 8, heads: int = 2;

    def add(op: Operation, inputs: dict[str, str] = {}) -> str {
        assert op.name not in self.ops, "duplicate node name";
        self.ops[op.name] = op;
        if not op.ports() { self +>: Seed() :+> op; }
        for (port, producer) in inputs.items() { self.wire(producer, op.name, port); }
        self.plan = None;
        self.analysis = None;
        return op.name;
    }
    def wire(producer: str, consumer: str, port: str) -> None {
        self.ops[producer] +>: TensorEdge(port=port) :+> self.ops[consumer];
    }
    def disconnect(producer: str, consumer: str, port: str) -> None {
        src = self.ops[producer];
        for e in [edge src->:TensorEdge:->] {
            if e.port == port and e.__jac__.target.archetype.name == consumer { del e; }
        }
    }
    def rewire(consumer: str, port: str, producer: str) -> None {
        for src in self.ops.values() { self.disconnect(src.name, consumer, port); }
        self.wire(producer, consumer, port);
    }
    def topology -> list[any] {
        links: list[any] = [];
        for src in self.ops.values() {
            assert src.name in self.ops and self.ops[src.name] is src;
            for e in [edge src->:TensorEdge:->] {
                dst = e.__jac__.target.archetype;
                assert isinstance(dst, Operation);
                assert dst.name in self.ops and self.ops[dst.name] is dst, "unregistered consumer";
                links.append([src.name, dst.name, e.port]);
            }
        }
        return links;
    }
    def fingerprint -> str {
        nodes = [(n.name, type(n).__name__, n.ports(), n.attributes()) for n in self.ops.values()];
        roots = sorted([n.name for n in [self->:Seed:->]]);
        return json.dumps({"nodes": nodes, "edges": sorted(self.topology()), "roots": roots}, sort_keys=True);
    }
    def to(device: str = "cpu", dtype: str = "float64") -> Model {
        assert dtype in ["float64", "float32"];
        resolved = torch.device(device);
        if resolved.type == "cuda" and resolved.index is None { resolved = torch.device("cuda", torch.cuda.current_device()); }
        self.device = str(resolved);
        self.precision = dtype;
        for op in self.ops.values() {
            if isinstance(op, Parameter) or isinstance(op, Constant) {
                target_dtype = getattr(torch, dtype) if op.value.is_floating_point() else op.value.dtype;
                op.value = op.value.to(device=resolved, dtype=target_dtype);
            }
        }
        self.plan = None;
        self.analysis = None;
        return self;
    }
    def inputs(source: any, target: any) -> dict[str, any] {
        return {"source": numerics.tokens(source, self.device, self.vocabulary, self.capacity),
                "target": numerics.tokens(target, self.device, self.vocabulary, self.capacity)};
    }
    def analyze(source: any, target: any) -> any {
        self.plan = None;
        self.analysis = None;
        values = self.inputs(source, target);
        run = self spawn Analyze(values=values);
        assert len(run.order) == len(self.ops), f"cycle or unreachable nodes: {[n for n in self.ops if n not in run.order]}";
        self.analysis = {"input_specs": {n: numerics.metadata(v) for (n, v) in values.items()},
                         "tensor_specs": run.outputs, "fingerprint": self.fingerprint()};
        # Scheduling/liveness plan is derived after successful metadata propagation.
        consumers = {n: [] for n in self.ops};
        for link in run.links { consumers[link[0]].append(link[1]); }
        persistent = [n.name for n in self.ops.values() if isinstance(n, Parameter) or isinstance(n, Constant)];
        self.plan = {"fingerprint": self.fingerprint(), "input_specs": {n: numerics.metadata(v) for (n, v) in values.items()},
                     "order": run.order, "specs": run.outputs, "links": run.links,
                     "consumers": consumers, "sources": run.sources,
                     "liveness": numerics.lifetime_report(run.order, run.outputs, consumers, persistent, "probabilities")};
        return self.plan;
    }
    def forward(source: any, target: any, capture: list[str] = []) -> any {
        values = self.inputs(source, target);
        specs = {n: numerics.metadata(v) for (n, v) in values.items()};
        if self.plan is None { self.analyze(source, target); }
        assert self.plan["fingerprint"] == self.fingerprint(), "graph/attributes changed: call analyze again";
        assert self.plan["input_specs"] == specs, "input metadata changed: call analyze again";
        assert all([n in self.ops for n in capture]), "unknown capture node";
        run = self spawn Execute(values=values, model=self, capture=capture);
        assert run.trace == self.plan["order"], "execution topology differs from analysis";
        return run;
    }
    def parameter_snapshot -> dict[str, any] {
        return {n.name: n.value.detach().clone() for n in self.ops.values() if isinstance(n, Parameter)};
    }
    def export_dot(filename: str) -> None {
        lines = ["digraph TransformerDataflow {", "rankdir=LR;"];
        for op in self.ops.values() {
            label = op.name + "\\n" + type(op).__name__;
            if self.plan is not None { label += "\\n" + str(self.plan["specs"][op.name]["shape"]); }
            lines.append(f'"{op.name}" [label="{label}"];');
        }
        for link in self.topology() { lines.append(f'"{link[0]}" -> "{link[1]}" [label="{link[2]}"];'); }
        lines.append("}");
        with open(filename, "w") as f { f.write("\n".join(lines) + "\n"); }
    }
    def export_analysis(filename: str) -> None {
        assert self.plan is not None;
        analysis_report = {"metadata_analysis": self.analysis, "order": self.plan["order"], "specs": self.plan["specs"], "edges": self.plan["links"],
                  "liveness": self.plan["liveness"],
                  "node_types": {n: type(op).__name__ for (n, op) in self.ops.items()},
                  "attributes": {n: op.attributes() for (n, op) in self.ops.items()}};
        with open(filename, "w") as f { json.dump(analysis_report, f, indent=2); }
    }
}

walker Analyze {
    has values: dict[str, any], order: list[str] = [], outputs: dict[str, any] = {},
        links: list[any] = [], sources: dict[str, any] = {};
    can start with Model entry {
        self.links = here.topology();
        self.sources = {n: {} for n in here.ops};
        for link in self.links {
            assert link[2] in here.ops[link[1]].ports(), f"unknown port: {link}";
            assert link[2] not in self.sources[link[1]], f"duplicate producer for port: {link}";
            self.sources[link[1]][link[2]] = link[0];
        }
        for n in here.ops.values() {
            assert sorted(self.sources[n.name]) == sorted(n.ports()), f"missing input: {n.name}";
            n.specs = {};
            n.done = False;
            n.queued = False;
            if isinstance(n, Input) { n.supplied_spec = numerics.metadata(self.values[n.name]); }
        }
        roots = [->:Seed:->];
        assert sorted([n.name for n in roots]) == sorted([n.name for n in here.ops.values() if not n.ports()]), "invalid roots";
        for n in roots { n.queued = True; visit n; }
    }
    can infer with Operation entry {
        assert here.ready(here.specs) and not here.done;
        try { here.spec = here.infer(); }
        except Exception as error { raise ValueError(f"metadata inference at {here.name}: {error}") from error; }
        here.done = True;
        self.order.append(here.name);
        self.outputs[here.name] = here.spec;
        for e in [edge ->:TensorEdge:->] {
            dst = e.__jac__.target.archetype;
            assert isinstance(dst, Operation);
            dst.specs[e.port] = here.spec;
            if dst.ready(dst.specs) and not dst.queued { dst.queued = True; visit dst; }
        }
    }
}

walker Execute {
    has values: dict[str, any], model: Model, capture: list[str] = [],
        captured: dict[str, any] = {}, trace: list[str] = [], deliveries: list[any] = [],
        remaining: dict[str, int] = {}, active: list[str] = [], lifetime_trace: list[any] = [],
        probabilities: any = None, handle_identity: list[any] = [];
    can start with Model entry {
        for n in here.ops.values() {
            n.inbox = {};
            n.output = None;
            n.done = False;
            n.queued = False;
            self.remaining[n.name] = len(here.plan["consumers"][n.name]);
            if isinstance(n, Input) { n.value = self.values[n.name]; }
        }
        for n in [->:Seed:->] { n.queued = True; visit n; }
    }
    can compute with Operation entry {
        assert here.ready(here.inbox) and not here.done;
        here.output = here.evaluate();
        if isinstance(here, Input) { here.value = None; }
        assert numerics.metadata(here.output) == self.model.plan["specs"][here.name], f"runtime metadata mismatch: {here.name}";
        here.done = True;
        self.trace.append(here.name);
        if here.name in self.capture { self.captured[here.name] = here.output; }
        if here.name == "probabilities" { self.probabilities = here.output; }
        if not isinstance(here, Parameter) and not isinstance(here, Constant) { self.active.append(here.name); }
        for e in [edge ->:TensorEdge:->] {
            dst = e.__jac__.target.archetype;
            assert isinstance(dst, Operation);
            assert e.port not in dst.inbox;
            dst.inbox[e.port] = here.output;
            self.handle_identity.append({"producer": here.name, "consumer": dst.name, "port": e.port, "same_object": dst.inbox[e.port] is here.output});
            self.deliveries.append([here.name, dst.name, e.port]);
            if dst.ready(dst.inbox) and not dst.queued { dst.queued = True; visit dst; }
        }
        released: list[str] = [];
        for src in self.model.plan["sources"][here.name].values() {
            self.remaining[src] -= 1;
            if self.remaining[src] == 0 and src != "probabilities" {
                self.model.ops[src].output = None;
                if src in self.active { self.active.remove(src); released.append(src); }
            }
        }
        here.inbox = {};
        if self.remaining[here.name] == 0 and here.name != "probabilities" {
            here.output = None;
            if here.name in self.active { self.active.remove(here.name); released.append(here.name); }
        }
        self.lifetime_trace.append({"node": here.name, "release": sorted(released), "live_after": sorted(self.active)});
    }
}

# These helpers build nodes/edges and initialize parameters; they never run forward computations.
def linear(m: Model, prefix: str, x: str, din: int, dout: int, rng: any) -> str {
    w = m.add(Parameter(name=prefix + ".weight", value=numerics.weight([din, dout], rng)));
    b = m.add(Parameter(name=prefix + ".bias", value=numerics.zeros([dout])));
    mm = m.add(MatMul(name=prefix + ".matmul"), {"a": x, "b": w});
    return m.add(Add(name=prefix), {"a": mm, "b": b});
}
def attention(m: Model, prefix: str, x: str, memory: str, d: int, h: int, rng: any, causal: bool = False) -> str {
    width = d // h;
    heads: dict[str, str] = {};
    for (letter, producer) in [("q", x), ("k", memory), ("v", memory)] {
        proj = linear(m, prefix + "." + letter, producer, d, d, rng);
        reshaped = m.add(Reshape(name=prefix + "." + letter + ".reshape", dimensions=[-1, h, width]), {"x": proj});
        heads[letter] = m.add(Transpose(name=prefix + "." + letter + ".heads"), {"x": reshaped});
    }
    kt = m.add(Transpose(name=prefix + ".k.transpose", dim0=-2, dim1=-1), {"x": heads["k"]});
    score = m.add(MatMul(name=prefix + ".score.matmul"), {"a": heads["q"], "b": kt});
    scale = m.add(Constant(name=prefix + ".scale", value=numerics.scalar(1 / math.sqrt(width))));
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
def norm(m: Model, prefix: str, main: str, residual_source: str, d: int) -> str {
    added = m.add(Add(name=prefix + ".residual"), {"a": main, "b": residual_source});
    mean = m.add(ReduceMean(name=prefix + ".mean"), {"x": added});
    center = m.add(Subtract(name=prefix + ".center"), {"a": added, "b": mean});
    square = m.add(Square(name=prefix + ".square"), {"x": center});
    variance = m.add(ReduceMean(name=prefix + ".variance"), {"x": square});
    epsilon = m.add(Constant(name=prefix + ".epsilon", value=numerics.scalar(1e-5)));
    stable = m.add(Add(name=prefix + ".stable"), {"a": variance, "b": epsilon});
    inv = m.add(Rsqrt(name=prefix + ".rsqrt"), {"x": stable});
    normalized = m.add(Multiply(name=prefix + ".normalized"), {"a": center, "b": inv});
    gamma = m.add(Parameter(name=prefix + ".gamma", value=numerics.ones([d])));
    beta = m.add(Parameter(name=prefix + ".beta", value=numerics.zeros([d])));
    scaled = m.add(Multiply(name=prefix + ".scaled"), {"a": normalized, "b": gamma});
    return m.add(Add(name=prefix), {"a": scaled, "b": beta});
}
def feed_forward(m: Model, prefix: str, x: str, d: int, hidden: int, rng: any) -> str {
    up = linear(m, prefix + ".up", x, d, hidden, rng);
    activated = m.add(ReLU(name=prefix + ".relu"), {"x": up});
    return linear(m, prefix + ".output", activated, hidden, d, rng);
}
def embedding(m: Model, prefix: str, token: str, d: int, v: int, rng: any) -> str {
    table = m.add(Parameter(name=prefix + ".table", value=numerics.weight([v, d], rng)));
    gather = m.add(Gather(name=prefix + ".gather"), {"table": table, "indices": token});
    return m.add(Multiply(name=prefix), {"a": gather, "b": "embedding_scale"});
}
def build(dimension: int = 8, heads: int = 2, hidden: int = 16, vocabulary: int = 13, capacity: int = 256) -> Model {
    assert dimension > 0 and heads >= 2 and dimension % heads == 0;
    assert hidden > 0 and vocabulary > 2 and capacity > 0;
    m = Model(dimension=dimension, heads=heads, vocabulary=vocabulary, capacity=capacity);
    rng = torch.Generator().manual_seed(1729);
    m.add(Input(name="source")); m.add(Input(name="target"));
    m.add(Constant(name="embedding_scale", value=numerics.scalar(math.sqrt(dimension))));
    m.add(Constant(name="position_table", value=numerics.position_table(capacity, dimension)));
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

def greedy(m: Model, source: any, steps: int = 4, bos: int = 1, eos: int = 2) -> list[int] {
    tokens = [bos];
    for step in range(steps) {
        # Shape-specialized analysis is deliberately rebuilt for the new prefix.
        m.analyze(source, tokens);
        run = m.forward(source, tokens);
        token = int(run.probabilities[-1].argmax().item());
        tokens.append(token);
        if token == eos { break; }
    }
    return tokens;
}
