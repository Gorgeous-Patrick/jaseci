"""Reusable, inference-only tensor dataflow primitives and one Compute walker."""
import torch;
import math;
import json;
import from jaclang.lib.tensor_graph { numerics, backend }

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

node TensorGraph {
    has ops: dict[str, Operation] = {}, analysis: any = None, plan: any = None,
        device: str = "cpu", precision: str = "float64", output_name: str = "";

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
        backend.validate_types(self);
        nodes = [(n.name, type(n).__name__, n.ports(), n.attributes()) for n in self.ops.values()];
        roots = sorted([n.name for n in [self->:Seed:->]]);
        return json.dumps({"output": self.output_name, "nodes": nodes, "edges": sorted(self.topology()), "roots": roots}, sort_keys=True);
    }
    def to(device: str = "cpu", dtype: str = "float64") -> TensorGraph {
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
    def prepare(values: dict[str, any]) -> any {
        self.plan = None;
        self.analysis = None;
        backend.check_feeds(self, values);
        backend.validate_types(self);
        assert self.output_name in self.ops, "missing selected output";
        run = self spawn Compute(values=values, metadata_only=True);
        assert len(run.order) == len(self.ops), f"cycle or unreachable nodes: {[n for n in self.ops if n not in run.order]}";
        self.analysis = {"input_specs": {n: numerics.metadata(v) for (n, v) in values.items()},
                         "tensor_specs": run.outputs, "fingerprint": self.fingerprint()};
        consumers = {n: [] for n in self.ops};
        for link in run.links { consumers[link[0]].append(link[1]); }
        persistent = [n.name for n in self.ops.values() if isinstance(n, Parameter) or isinstance(n, Constant)];
        self.plan = {"fingerprint": self.analysis["fingerprint"], "input_specs": self.analysis["input_specs"],
                     "order": run.order, "specs": run.outputs, "links": run.links,
                     "consumers": consumers, "sources": run.sources,
                     "liveness": numerics.lifetime_report(run.order, run.outputs, consumers, persistent, self.output_name)};
        return self.plan;
    }
    def check(values: dict[str, any], capture: list[str] = []) -> None {
        backend.check_feeds(self, values);
        if self.plan is None { self.prepare(values); }
        assert self.plan["fingerprint"] == self.fingerprint(), "graph/attributes changed: call prepare again";
        specs = {n: numerics.metadata(v) for (n, v) in values.items()};
        assert self.plan["input_specs"] == specs, "input metadata changed: call prepare again";
        assert all([n in self.ops for n in capture]), "unknown capture node";
    }
    def run(values: dict[str, any], capture: list[str] = []) -> any {
        self.check(values, capture);
        run = self spawn Compute(values=values, capture=capture);
        assert run.trace == self.plan["order"], "execution topology differs from analysis";
        return run;
    }
    def compile(values: dict[str, any], engine: str = "fx", capture: list[str] = []) -> any {
        self.prepare(values);
        return backend.compile_graph(self, engine, capture);
    }
    def parameter_snapshot -> dict[str, any] {
        return {n.name: n.value.detach().clone() for n in self.ops.values() if isinstance(n, Parameter)};
    }
    def export_dot(filename: str) -> None {
        lines = ["digraph TensorGraph {", "rankdir=LR;"];
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
        analysis_report = {"order": self.plan["order"], "specs": self.plan["specs"], "edges": self.plan["links"],
                           "liveness": self.plan["liveness"],
                           "node_types": {n: type(op).__name__ for (n, op) in self.ops.items()},
                           "attributes": {n: op.attributes() for (n, op) in self.ops.items()}};
        with open(filename, "w") as f { json.dump(analysis_report, f, indent=2); }
    }
}

walker Compute {
    has values: dict[str, any], metadata_only: bool = False, model: any = None,
        order: list[str] = [], outputs: dict[str, any] = {}, links: list[any] = [], sources: dict[str, any] = {},
        capture: list[str] = [], captured: dict[str, any] = {}, trace: list[str] = [], deliveries: list[any] = [],
        remaining: dict[str, int] = {}, active: list[str] = [], lifetime_trace: list[any] = [],
        output: any = None, handle_identity: list[any] = [];

    can start with TensorGraph entry {
        self.model = here;
        if self.metadata_only {
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
        } else {
            here.check(self.values, self.capture);
            for n in here.ops.values() {
                n.inbox = {};
                n.output = None;
                n.done = False;
                n.queued = False;
                self.remaining[n.name] = len(here.plan["consumers"][n.name]);
                if isinstance(n, Input) { n.value = self.values[n.name]; }
            }
        }
        roots = [->:Seed:->];
        assert sorted([n.name for n in roots]) == sorted([n.name for n in here.ops.values() if not n.ports()]), "invalid roots";
        for n in roots { n.queued = True; visit n; }
    }
    can compute with Operation entry {
        if self.metadata_only {
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
        } else {
            assert here.ready(here.inbox) and not here.done;
            with torch.inference_mode() { here.output = here.evaluate(); }
            if isinstance(here, Input) { here.value = None; }
            assert numerics.metadata(here.output) == self.model.plan["specs"][here.name], f"runtime metadata mismatch: {here.name}";
            here.done = True;
            self.trace.append(here.name);
            if here.name in self.capture { self.captured[here.name] = here.output; }
            if here.name == self.model.output_name { self.output = here.output; }
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
                if self.remaining[src] == 0 and src != self.model.output_name {
                    self.model.ops[src].output = None;
                    if src in self.active { self.active.remove(src); released.append(src); }
                }
            }
            here.inbox = {};
            if self.remaining[here.name] == 0 and here.name != self.model.output_name {
                here.output = None;
                if here.name in self.active { self.active.remove(here.name); released.append(here.name); }
            }
            self.lifetime_trace.append({"node": here.name, "release": sorted(released), "live_after": sorted(self.active)});
        }
    }
}
