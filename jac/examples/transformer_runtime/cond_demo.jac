"""Library Cond: branch inputs are lazy result references, not eager tensors."""
import torch;
import os;
import from jaclang.lib.tensor_graph {
    TensorGraph, Compute, Input, Parameter, Constant, Greater, MatMul, Add, Subtract, Cond
}
with entry {
    tg = TensorGraph(output_name="choose");
    tg.add(Input(name="signal"));
    tg.add(Input(name="x"));
    tg.add(Parameter(name="weight", value=torch.eye(2, dtype=torch.float64)));
    tg.add(Constant(name="zero", value=torch.tensor(0.0, dtype=torch.float64)));
    tg.add(Greater(name="predicate"), {"a": "signal", "b": "zero"});
    tg.add(MatMul(name="common"), {"a": "x", "b": "weight"});
    tg.add(Add(name="true"), {"a": "common", "b": "signal"});
    tg.add(Subtract(name="false"), {"a": "common", "b": "signal"});
    tg.add(Cond(name="choose"), {"condition": "predicate", "true_result": "true", "false_result": "false"});
    feeds = {"signal": torch.tensor(0.5, dtype=torch.float64), "x": torch.eye(2, dtype=torch.float64)};
    fx = tg.compile(feeds);
    for value in [0.5, -0.5] {
        feeds["signal"] = torch.tensor(value, dtype=torch.float64);
        run = tg spawn Compute(values=feeds);
        torch.testing.assert_close(run.output, fx(feeds).output);
        print("signal:", value, "trace:", run.trace, "output:", run.output);
    }
    print("precomputed:", tg.plan["conditional"]["pre"]);
    root_dir = os.path.dirname(__file__);
    fx.export(os.path.join(root_dir, "results", "cond_demo_fx.py"));
    tg.export_dot(os.path.join(root_dir, "results", "cond_demo.dot"));
}
