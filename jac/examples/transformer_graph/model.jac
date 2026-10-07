"""Typed Transformer module nodes; only the walker executes the forward graph."""
import math_cpu;
import math;
import random;
import copy;
import tensor_ops;

glob D: int = 8, HEADS: int = 2, FF: int = 16, VOCAB: int = 13, SEED: int = 1729;

edge Flow {
    has role: str, path: str;
}

node Module {
    # Common scheduling state only. Concrete nodes declare their parameters.
    has name: str, required: list[str] = ["x"], inbox: dict[str, any] = {},
        output: any = None, diagnostics: dict[str, any] = {},
        done: bool = False, queued: bool = False, tensor_api: any = None;

    def ready -> bool {
        return all([role in self.inbox for role in self.required]);
    }

    def initialize(rng: any) -> None {}
    def parameters -> dict[str, any] { return {}; }
    def evaluate -> None { raise NotImplementedError("Concrete module required"); }
}

node Input(Module) {
    override def evaluate -> None { self.output = self.inbox["tokens"]; }
}

node Embedding(Module) {
    has table: any = [], dimension: int = D, vocabulary: int = VOCAB;

    override def initialize(rng: any) -> None {
        self.table = math_cpu.random_matrix(self.vocabulary, self.dimension, rng);
    }
    override def parameters -> dict[str, any] { return {"table": self.table}; }
    override def evaluate -> None {
        tokens = self.inbox["x"];
        if self.tensor_api is not None {
            self.output = self.tensor_api.index_select(self.table, 0, tokens) * math.sqrt(self.dimension);
            return;
        }
        if not tokens or any([type(t) is not int or not 0 <= t < self.vocabulary for t in tokens]) {
            raise ValueError("Token sequences must be nonempty integer IDs in vocabulary");
        }
        self.output = [[v * math.sqrt(self.dimension) for v in self.table[t]] for t in tokens];
    }
}

node PositionalEncoding(Module) {
    has dimension: int = D, position_cache: dict[int, any] = {};

    override def evaluate -> None {
        x = self.inbox["x"];
        if self.tensor_api is not None {
            t = self.tensor_api;
            length = x.shape[0];
            if length not in self.position_cache {
                positions = t.arange(length, device=x.device, dtype=x.dtype).unsqueeze(1);
                channels = t.arange(self.dimension, device=x.device, dtype=x.dtype);
                frequencies = t.pow(10000.0, -2.0 * t.floor(channels / 2.0) / self.dimension);
                angles = positions * frequencies;
                even = t.eq(t.remainder(channels.to(t.int64), 2), 0).unsqueeze(0);
                waves = t.where(even, t.sin(angles), t.cos(angles));
                self.position_cache[length] = waves;
            }
            self.output = x + self.position_cache[length];
            return;
        }
        result: any = [];
        for (pos, row) in enumerate(x) {
            encoded: any = [];
            for i in range(self.dimension) {
                angle = pos / 10000 ** (2 * (i // 2) / self.dimension);
                wave = math.sin(angle) if i % 2 == 0 else math.cos(angle);
                encoded.append(row[i] + wave);
            }
            result.append(encoded);
        }
        self.output = result;
    }
}

node AttentionOps(Module) {
    # Shared nonparametric head arithmetic; never instantiated in the graph.
    has dimension: int = D, heads: int = HEADS, mask_cache: dict[int, any] = {};

    def head_context(q: any, k: any, v: any, causal: bool) -> any {
        width = self.dimension // self.heads;
        if self.tensor_api is not None {
            t = self.tensor_api;
            q_heads = q.reshape(q.shape[0], self.heads, width).transpose(0, 1);
            k_heads = k.reshape(k.shape[0], self.heads, width).transpose(0, 1);
            v_heads = v.reshape(v.shape[0], self.heads, width).transpose(0, 1);
            scores = t.matmul(q_heads, k_heads.transpose(-2, -1)) / math.sqrt(width);
            if causal {
                length = q.shape[0];
                if length not in self.mask_cache {
                    self.mask_cache[length] = t.ones((length, length), dtype=t.bool, device=q.device).triu(1);
                }
                scores = scores.masked_fill(self.mask_cache[length], -math.inf);
            }
            probabilities = t.softmax(scores, dim=-1);
            context = t.matmul(probabilities, v_heads);
            self.diagnostics["attention"] = probabilities;
            return context.transpose(0, 1).contiguous().reshape(q.shape[0], self.dimension);
        }
        joined = math_cpu.zeros(len(q), self.dimension);
        maps: list[any] = [];
        for head in range(self.heads) {
            start = head * width;
            stop = start + width;
            q_head = [row[start:stop] for row in q];
            k_head = [row[start:stop] for row in k];
            v_head = [row[start:stop] for row in v];
            scores = math_cpu.scale(math_cpu.matmul(q_head, math_cpu.transpose(k_head)),
                                    1.0 / math.sqrt(width));
            if causal {
                for t in range(len(q)) {
                    for s in range(t + 1, len(k)) { scores[t][s] = -math.inf; }
                }
            }
            probabilities = [math_cpu.softmax(row) for row in scores];
            maps.append(probabilities);
            context = math_cpu.matmul(probabilities, v_head);
            for t in range(len(q)) {
                for i in range(width) { joined[t][start + i] = context[t][i]; }
            }
        }
        self.diagnostics["attention"] = maps;
        return joined;
    }

}

node SelfAttention(AttentionOps) {
    has w_q: any = [], b_q: any = [],
        w_k: any = [], b_k: any = [],
        w_v: any = [], b_v: any = [],
        w_o: any = [], b_o: any = [];
    override def initialize(rng: any) -> None {
        assert self.dimension % self.heads == 0;
        self.w_q = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_q = [0.0] * self.dimension;
        self.w_k = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_k = [0.0] * self.dimension;
        self.w_v = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_v = [0.0] * self.dimension;
        self.w_o = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_o = [0.0] * self.dimension;
    }
    override def parameters -> dict[str, any] {
        return {"w_q": self.w_q, "b_q": self.b_q, "w_k": self.w_k, "b_k": self.b_k,
                "w_v": self.w_v, "b_v": self.b_v, "w_o": self.w_o, "b_o": self.b_o};
    }

    override def evaluate -> None {
        x = self.inbox["x"];
        memory = self.inbox["x"];
        if self.tensor_api is not None {
            t = self.tensor_api;
            q = t.matmul(x, self.w_q) + self.b_q;
            k = t.matmul(memory, self.w_k) + self.b_k;
            v = t.matmul(memory, self.w_v) + self.b_v;
            joined = self.head_context(q, k, v, False);
            self.output = t.matmul(joined, self.w_o) + self.b_o;
            return;
        }
        q = math_cpu.affine(x, self.w_q, self.b_q);
        k = math_cpu.affine(memory, self.w_k, self.b_k);
        v = math_cpu.affine(memory, self.w_v, self.b_v);
        joined = self.head_context(q, k, v, False);
        self.output = math_cpu.affine(joined, self.w_o, self.b_o);
    }
}

node CausalSelfAttention(AttentionOps) {
    has w_q: any = [], b_q: any = [],
        w_k: any = [], b_k: any = [],
        w_v: any = [], b_v: any = [],
        w_o: any = [], b_o: any = [];
    override def initialize(rng: any) -> None {
        assert self.dimension % self.heads == 0;
        self.w_q = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_q = [0.0] * self.dimension;
        self.w_k = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_k = [0.0] * self.dimension;
        self.w_v = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_v = [0.0] * self.dimension;
        self.w_o = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_o = [0.0] * self.dimension;
    }
    override def parameters -> dict[str, any] {
        return {"w_q": self.w_q, "b_q": self.b_q, "w_k": self.w_k, "b_k": self.b_k,
                "w_v": self.w_v, "b_v": self.b_v, "w_o": self.w_o, "b_o": self.b_o};
    }

    override def evaluate -> None {
        x = self.inbox["x"];
        memory = self.inbox["x"];
        if self.tensor_api is not None {
            t = self.tensor_api;
            q = t.matmul(x, self.w_q) + self.b_q;
            k = t.matmul(memory, self.w_k) + self.b_k;
            v = t.matmul(memory, self.w_v) + self.b_v;
            joined = self.head_context(q, k, v, True);
            self.output = t.matmul(joined, self.w_o) + self.b_o;
            return;
        }
        q = math_cpu.affine(x, self.w_q, self.b_q);
        k = math_cpu.affine(memory, self.w_k, self.b_k);
        v = math_cpu.affine(memory, self.w_v, self.b_v);
        joined = self.head_context(q, k, v, True);
        self.output = math_cpu.affine(joined, self.w_o, self.b_o);
    }
}

node CrossAttention(AttentionOps) {
    has w_q: any = [], b_q: any = [],
        w_k: any = [], b_k: any = [],
        w_v: any = [], b_v: any = [],
        w_o: any = [], b_o: any = [];
    override def initialize(rng: any) -> None {
        assert self.dimension % self.heads == 0;
        self.w_q = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_q = [0.0] * self.dimension;
        self.w_k = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_k = [0.0] * self.dimension;
        self.w_v = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_v = [0.0] * self.dimension;
        self.w_o = math_cpu.random_matrix(self.dimension, self.dimension, rng);
        self.b_o = [0.0] * self.dimension;
    }
    override def parameters -> dict[str, any] {
        return {"w_q": self.w_q, "b_q": self.b_q, "w_k": self.w_k, "b_k": self.b_k,
                "w_v": self.w_v, "b_v": self.b_v, "w_o": self.w_o, "b_o": self.b_o};
    }

    override def evaluate -> None {
        x = self.inbox["x"];
        memory = self.inbox["memory"];
        if self.tensor_api is not None {
            t = self.tensor_api;
            q = t.matmul(x, self.w_q) + self.b_q;
            k = t.matmul(memory, self.w_k) + self.b_k;
            v = t.matmul(memory, self.w_v) + self.b_v;
            joined = self.head_context(q, k, v, False);
            self.output = t.matmul(joined, self.w_o) + self.b_o;
            return;
        }
        q = math_cpu.affine(x, self.w_q, self.b_q);
        k = math_cpu.affine(memory, self.w_k, self.b_k);
        v = math_cpu.affine(memory, self.w_v, self.b_v);
        joined = self.head_context(q, k, v, False);
        self.output = math_cpu.affine(joined, self.w_o, self.b_o);
    }
}

node FeedForward(Module) {
    has w_up: any = [], b_up: any = [],
        w_down: any = [], b_down: any = [],
        dimension: int = D, hidden: int = FF;

    override def initialize(rng: any) -> None {
        self.w_up = math_cpu.random_matrix(self.dimension, self.hidden, rng);
        self.b_up = [0.0] * self.hidden;
        self.w_down = math_cpu.random_matrix(self.hidden, self.dimension, rng);
        self.b_down = [0.0] * self.dimension;
    }
    override def parameters -> dict[str, any] {
        return {"w_up": self.w_up, "b_up": self.b_up,
                "w_down": self.w_down, "b_down": self.b_down};
    }
    override def evaluate -> None {
        if self.tensor_api is not None {
            t = self.tensor_api;
            hidden = t.matmul(self.inbox["x"], self.w_up) + self.b_up;
            activated = t.relu(hidden);
            self.output = t.matmul(activated, self.w_down) + self.b_down;
            return;
        }
        hidden = math_cpu.affine(self.inbox["x"], self.w_up, self.b_up);
        activated = math_cpu.relu(hidden);
        self.output = math_cpu.affine(activated, self.w_down, self.b_down);
    }
}

node AddNorm(Module) {
    has gamma: any = [], beta: any = [], dimension: int = D,
        epsilon: float = 1e-5;

    override def initialize(rng: any) -> None {
        self.gamma = [1.0] * self.dimension;
        self.beta = [0.0] * self.dimension;
    }
    override def parameters -> dict[str, any] { return {"gamma": self.gamma, "beta": self.beta}; }
    override def evaluate -> None {
        if self.tensor_api is not None {
            t = self.tensor_api;
            summed_tensor = self.inbox["main"] + self.inbox["skip"];
            mean_tensor = summed_tensor.mean(dim=-1, keepdim=True);
            centered = summed_tensor - mean_tensor;
            variance_tensor = centered.square().mean(dim=-1, keepdim=True);
            self.output = centered * t.rsqrt(variance_tensor + self.epsilon) * self.gamma + self.beta;
            return;
        }
        summed = math_cpu.add(self.inbox["main"], self.inbox["skip"]);
        result: any = [];
        for row in summed {
            mean = sum(row) / self.dimension;
            variance = sum([(v - mean) ** 2 for v in row]) / self.dimension;
            inverse_std = 1.0 / math.sqrt(variance + self.epsilon);
            result.append([(row[i] - mean) * inverse_std * self.gamma[i] + self.beta[i]
                           for i in range(self.dimension)]);
        }
        self.output = result;
    }
}

node Linear(Module) {
    has weight: any = [], bias: any = [],
        input_dimension: int = D, output_dimension: int = VOCAB;

    override def initialize(rng: any) -> None {
        self.weight = math_cpu.random_matrix(self.input_dimension, self.output_dimension, rng);
        self.bias = [0.0] * self.output_dimension;
    }
    override def parameters -> dict[str, any] { return {"weight": self.weight, "bias": self.bias}; }
    override def evaluate -> None {
        if self.tensor_api is not None {
            self.output = self.tensor_api.matmul(self.inbox["x"], self.weight) + self.bias;
            return;
        }
        self.output = math_cpu.affine(self.inbox["x"], self.weight, self.bias);
    }
}

node Softmax(Module) {
    override def evaluate -> None {
        if self.tensor_api is not None { self.output = self.tensor_api.softmax(self.inbox["x"], dim=-1); }
        else { self.output = [math_cpu.softmax(row) for row in self.inbox["x"]]; }
    }
}

node Model {
    has modules: dict[str, Module] = {}, device: str = "", precision: str = "float64",
        vocabulary: int = VOCAB, record_trace: bool = True, profile_nodes: bool = False;

    def to(device: str, dtype: str = "float64") -> Model {
        assert dtype in ["float64", "float32"];
        t = tensor_ops.torch_api();
        self.device = tensor_ops.device_name(device);
        self.precision = dtype;
        for n in self.modules.values() {
            for (field_name, value) in n.parameters().items() {
                setattr(n, field_name, tensor_ops.parameter(value, self.device, dtype));
            }
            n.tensor_api = t;
            if isinstance(n, PositionalEncoding) { n.position_cache = {}; }
            if isinstance(n, AttentionOps) { n.mask_cache = {}; }
        }
        return self;
    }

    def add(module: Module, rng: any) -> None {
        assert module.name not in self.modules;
        module.initialize(rng);
        self.modules[module.name] = module;
    }
    def parameter_snapshot -> dict[str, any] {
        return copy.deepcopy({name: n.parameters() for (name, n) in self.modules.items()});
    }
    def wire(source: str, target: str, role: str, path: str) -> None {
        self.modules[source] +>: Flow(role=role, path=path) :+> self.modules[target];
    }
    def forward(source: any, shifted_target: any) -> any {
        if self.device {
            source = tensor_ops.tokens(source, self.device, self.vocabulary);
            shifted_target = tensor_ops.tokens(shifted_target, self.device, self.vocabulary);
        }
        run = self spawn Infer(source=source, target=shifted_target, record_trace=self.record_trace,
                              profile_nodes=self.profile_nodes);
        assert run.executed == len(self.modules), "Unsatisfied dependency or disconnected module";
        assert self.modules["probabilities"].done;
        return run;
    }
    def schedule_replay(source: any, target: any) -> any {
        # Measurement only: replay previously computed handles through the same scheduler.
        outputs = {name: n.output for (name, n) in self.modules.items()};
        run = self spawn Infer(source=source, target=target, record_trace=False, replay_outputs=outputs);
        assert run.executed == len(self.modules);
        return run;
    }
    def rewire_encoder_skip(alternate: bool) -> None {
        pos = self.modules["enc_pos"];
        attn = self.modules["enc_attn"];
        del [edge pos->:Flow:role == "skip":->];
        del [edge attn->:Flow:role == "skip":->];
        origin = "enc_attn" if alternate else "enc_pos";
        self.wire(origin, "enc_norm1", "skip", "residual");
    }
    def remove_encoder_memory -> None {
        memory = self.modules["enc_norm2"];
        del [edge memory->:Flow:->];
    }
    def export_dot(filename: str) -> None {
        lines = ["digraph Transformer {", "  rankdir=LR;"];
        lines.append('  "model" [shape=diamond,label="Model / Infer entry"];');
        for e in [edge self->:Flow:->] {
            target = e.__jac__.target.archetype;
            lines.append(f'  "model" -> "{target.name}" [label="{e.path}:{e.role}"];');
        }
        for n in self.modules.values() {
            typename = type(n).__name__;
            lines.append(f'  "{n.name}" [label="{n.name}\\n{typename}"];');
            for e in [edge n->:Flow:->] {
                target = e.__jac__.target.archetype;
                lines.append(f'  "{n.name}" -> "{target.name}" [label="{e.path}:{e.role}"];');
            }
        }
        lines.append("}");
        with open(filename, "w") as f { f.write("\n".join(lines) + "\n"); }
    }
}

walker Infer {
    has source: any, target: any, trace: list[str] = [], deliveries: list[any] = [],
        probabilities: any = None, executed: int = 0, record_trace: bool = True,
        profile_nodes: bool = False, replay_outputs: dict[str, any] = {};

    can start with Model entry {
        for n in here.modules.values() {
            n.inbox = {};
            n.output = None;
            n.diagnostics = {};
            n.done = False;
            n.queued = False;
        }
        here.modules["source"].inbox["tokens"] = self.source;
        here.modules["target"].inbox["tokens"] = self.target;
        for n in [->:Flow:->] {
            assert n.ready();
            n.queued = True;
            visit n;
        }
    }
    can execute with Module entry {
        assert here.ready() and not here.done;
        if self.replay_outputs { here.output = self.replay_outputs[here.name]; }
        elif self.profile_nodes and here.tensor_api is not None {
            with here.tensor_api.profiler.record_function("Jac.node/" + here.name) { here.evaluate(); }
        } else { here.evaluate(); }
        here.done = True;
        self.executed += 1;
        if self.record_trace { self.trace.append(here.name); }
        if isinstance(here, Softmax) { self.probabilities = here.output; }
        for e in [edge ->:Flow:->] {
            destination = e.__jac__.target.archetype;
            assert isinstance(destination, Module);
            assert e.role in destination.required, "Unexpected input role";
            assert e.role not in destination.inbox, "Duplicate input role";
            destination.inbox[e.role] = here.output;
            if self.record_trace { self.deliveries.append((here.name, destination.name, e.role)); }
            if destination.ready() and not destination.queued {
                destination.queued = True;
                visit destination;
            }
        }
    }
}

def build(dimension: int = D, heads: int = HEADS, hidden: int = FF, vocabulary: int = VOCAB) -> Model {
    assert dimension > 0 and heads >= 2 and dimension % heads == 0;
    m = Model(vocabulary=vocabulary);
    rng = random.Random(SEED);
    modules: list[Module] = [
        Input(name="source", required=["tokens"]), Input(name="target", required=["tokens"]),
        Embedding(name="enc_embed", dimension=dimension, vocabulary=vocabulary), PositionalEncoding(name="enc_pos", dimension=dimension),
        SelfAttention(name="enc_attn", dimension=dimension, heads=heads), AddNorm(name="enc_norm1", required=["main", "skip"], dimension=dimension),
        FeedForward(name="enc_ffn", dimension=dimension, hidden=hidden), AddNorm(name="enc_norm2", required=["main", "skip"], dimension=dimension),
        Embedding(name="dec_embed", dimension=dimension, vocabulary=vocabulary), PositionalEncoding(name="dec_pos", dimension=dimension),
        CausalSelfAttention(name="dec_attn", dimension=dimension, heads=heads), AddNorm(name="dec_norm1", required=["main", "skip"], dimension=dimension),
        CrossAttention(name="cross_attn", required=["x", "memory"], dimension=dimension, heads=heads),
        AddNorm(name="dec_norm2", required=["main", "skip"], dimension=dimension), FeedForward(name="dec_ffn", dimension=dimension, hidden=hidden),
        AddNorm(name="dec_norm3", required=["main", "skip"], dimension=dimension),
        Linear(name="projection", input_dimension=dimension, output_dimension=vocabulary), Softmax(name="probabilities")
    ];
    for module in modules { m.add(module, rng); }
    m +>: Flow(role="entry", path="seed") :+> m.modules["source"];
    m +>: Flow(role="entry", path="seed") :+> m.modules["target"];
    links = [
        ("source", "enc_embed", "x", "main"), ("enc_embed", "enc_pos", "x", "main"),
        ("enc_pos", "enc_attn", "x", "main"), ("enc_attn", "enc_norm1", "main", "main"),
        ("enc_pos", "enc_norm1", "skip", "residual"),
        ("enc_norm1", "enc_ffn", "x", "main"), ("enc_ffn", "enc_norm2", "main", "main"),
        ("enc_norm1", "enc_norm2", "skip", "residual"),
        ("target", "dec_embed", "x", "main"), ("dec_embed", "dec_pos", "x", "main"),
        ("dec_pos", "dec_attn", "x", "main"), ("dec_attn", "dec_norm1", "main", "main"),
        ("dec_pos", "dec_norm1", "skip", "residual"),
        ("dec_norm1", "cross_attn", "x", "main"),
        ("enc_norm2", "cross_attn", "memory", "encoder_memory"),
        ("cross_attn", "dec_norm2", "main", "main"),
        ("dec_norm1", "dec_norm2", "skip", "residual"),
        ("dec_norm2", "dec_ffn", "x", "main"), ("dec_ffn", "dec_norm3", "main", "main"),
        ("dec_norm2", "dec_norm3", "skip", "residual"),
        ("dec_norm3", "projection", "x", "main"),
        ("projection", "probabilities", "x", "main")
    ];
    for link in links { m.wire(link[0], link[1], link[2], link[3]); }
    return m;
}

def greedy(m: Model, source: any, bos: int = 1, eos: int = 2, steps: int = 5) -> list[int] {
    tokens = [bos];
    for i in range(steps) {
        run = m.forward(source, tokens);
        row = run.probabilities[-1];
        token = tensor_ops.argmax(row) if m.device else math_cpu.argmax(row);
        tokens.append(token);
        if token == eos { break; }
    }
    return tokens;
}
