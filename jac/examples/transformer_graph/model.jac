"""Typed Transformer module nodes; only the walker executes the forward graph."""
import math_cpu;
import math;
import random;
import copy;

glob D: int = 8, HEADS: int = 2, FF: int = 16, VOCAB: int = 13, SEED: int = 1729;

edge Flow {
    has role: str, path: str;
}

node Module {
    # Common scheduling state only. Concrete nodes declare their parameters.
    has name: str, required: list[str] = ["x"], inbox: dict[str, any] = {},
        output: any = None, diagnostics: dict[str, any] = {},
        done: bool = False, queued: bool = False;

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
    has table: list[list[float]] = [], dimension: int = D, vocabulary: int = VOCAB;

    override def initialize(rng: any) -> None {
        self.table = math_cpu.random_matrix(self.vocabulary, self.dimension, rng);
    }
    override def parameters -> dict[str, any] { return {"table": self.table}; }
    override def evaluate -> None {
        tokens = self.inbox["x"];
        if not tokens or any([type(t) is not int or not 0 <= t < self.vocabulary for t in tokens]) {
            raise ValueError("Token sequences must be nonempty integer IDs in vocabulary");
        }
        self.output = [[v * math.sqrt(self.dimension) for v in self.table[t]] for t in tokens];
    }
}

node PositionalEncoding(Module) {
    has dimension: int = D;

    override def evaluate -> None {
        x = self.inbox["x"];
        result: list[list[float]] = [];
        for (pos, row) in enumerate(x) {
            encoded: list[float] = [];
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
    has dimension: int = D, heads: int = HEADS;

    def head_context(q: list[list[float]], k: list[list[float]], v: list[list[float]],
                     causal: bool) -> list[list[float]] {
        width = self.dimension // self.heads;
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
    has w_q: list[list[float]] = [], b_q: list[float] = [],
        w_k: list[list[float]] = [], b_k: list[float] = [],
        w_v: list[list[float]] = [], b_v: list[float] = [],
        w_o: list[list[float]] = [], b_o: list[float] = [];
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
        q = math_cpu.affine(x, self.w_q, self.b_q);
        k = math_cpu.affine(memory, self.w_k, self.b_k);
        v = math_cpu.affine(memory, self.w_v, self.b_v);
        joined = self.head_context(q, k, v, False);
        self.output = math_cpu.affine(joined, self.w_o, self.b_o);
    }
}

node CausalSelfAttention(AttentionOps) {
    has w_q: list[list[float]] = [], b_q: list[float] = [],
        w_k: list[list[float]] = [], b_k: list[float] = [],
        w_v: list[list[float]] = [], b_v: list[float] = [],
        w_o: list[list[float]] = [], b_o: list[float] = [];
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
        q = math_cpu.affine(x, self.w_q, self.b_q);
        k = math_cpu.affine(memory, self.w_k, self.b_k);
        v = math_cpu.affine(memory, self.w_v, self.b_v);
        joined = self.head_context(q, k, v, True);
        self.output = math_cpu.affine(joined, self.w_o, self.b_o);
    }
}

node CrossAttention(AttentionOps) {
    has w_q: list[list[float]] = [], b_q: list[float] = [],
        w_k: list[list[float]] = [], b_k: list[float] = [],
        w_v: list[list[float]] = [], b_v: list[float] = [],
        w_o: list[list[float]] = [], b_o: list[float] = [];
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
        q = math_cpu.affine(x, self.w_q, self.b_q);
        k = math_cpu.affine(memory, self.w_k, self.b_k);
        v = math_cpu.affine(memory, self.w_v, self.b_v);
        joined = self.head_context(q, k, v, False);
        self.output = math_cpu.affine(joined, self.w_o, self.b_o);
    }
}

node FeedForward(Module) {
    has w_up: list[list[float]] = [], b_up: list[float] = [],
        w_down: list[list[float]] = [], b_down: list[float] = [],
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
        hidden = math_cpu.affine(self.inbox["x"], self.w_up, self.b_up);
        activated = math_cpu.relu(hidden);
        self.output = math_cpu.affine(activated, self.w_down, self.b_down);
    }
}

node AddNorm(Module) {
    has gamma: list[float] = [], beta: list[float] = [], dimension: int = D,
        epsilon: float = 1e-5;

    override def initialize(rng: any) -> None {
        self.gamma = [1.0] * self.dimension;
        self.beta = [0.0] * self.dimension;
    }
    override def parameters -> dict[str, any] { return {"gamma": self.gamma, "beta": self.beta}; }
    override def evaluate -> None {
        summed = math_cpu.add(self.inbox["main"], self.inbox["skip"]);
        result: list[list[float]] = [];
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
    has weight: list[list[float]] = [], bias: list[float] = [],
        input_dimension: int = D, output_dimension: int = VOCAB;

    override def initialize(rng: any) -> None {
        self.weight = math_cpu.random_matrix(self.input_dimension, self.output_dimension, rng);
        self.bias = [0.0] * self.output_dimension;
    }
    override def parameters -> dict[str, any] { return {"weight": self.weight, "bias": self.bias}; }
    override def evaluate -> None {
        self.output = math_cpu.affine(self.inbox["x"], self.weight, self.bias);
    }
}

node Softmax(Module) {
    override def evaluate -> None { self.output = [math_cpu.softmax(row) for row in self.inbox["x"]]; }
}

node Model {
    has modules: dict[str, Module] = {};

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
    def forward(source: list[int], shifted_target: list[int]) -> any {
        run = self spawn Infer(source=source, target=shifted_target);
        assert len(run.trace) == len(self.modules), "Unsatisfied dependency or disconnected module";
        assert self.modules["probabilities"].done;
        return run;
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
    has source: list[int], target: list[int], trace: list[str] = [], deliveries: list[any] = [],
        probabilities: any = None;

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
        here.evaluate();
        here.done = True;
        self.trace.append(here.name);
        if isinstance(here, Softmax) { self.probabilities = here.output; }
        for e in [edge ->:Flow:->] {
            destination = e.__jac__.target.archetype;
            assert isinstance(destination, Module);
            assert e.role in destination.required, "Unexpected input role";
            assert e.role not in destination.inbox, "Duplicate input role";
            destination.inbox[e.role] = here.output;
            self.deliveries.append((here.name, destination.name, e.role));
            if destination.ready() and not destination.queued {
                destination.queued = True;
                visit destination;
            }
        }
    }
}

def build -> Model {
    m = Model();
    rng = random.Random(SEED);
    modules: list[Module] = [
        Input(name="source", required=["tokens"]), Input(name="target", required=["tokens"]),
        Embedding(name="enc_embed"), PositionalEncoding(name="enc_pos"),
        SelfAttention(name="enc_attn"), AddNorm(name="enc_norm1", required=["main", "skip"]),
        FeedForward(name="enc_ffn"), AddNorm(name="enc_norm2", required=["main", "skip"]),
        Embedding(name="dec_embed"), PositionalEncoding(name="dec_pos"),
        CausalSelfAttention(name="dec_attn"), AddNorm(name="dec_norm1", required=["main", "skip"]),
        CrossAttention(name="cross_attn", required=["x", "memory"]),
        AddNorm(name="dec_norm2", required=["main", "skip"]), FeedForward(name="dec_ffn"),
        AddNorm(name="dec_norm3", required=["main", "skip"]),
        Linear(name="projection"), Softmax(name="probabilities")
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

def greedy(m: Model, source: list[int], bos: int = 1, eos: int = 2, steps: int = 5) -> list[int] {
    tokens = [bos];
    for i in range(steps) {
        run = m.forward(source, tokens);
        row = run.probabilities[-1];
        token = math_cpu.argmax(row);
        tokens.append(token);
        if token == eos { break; }
    }
    return tokens;
}
