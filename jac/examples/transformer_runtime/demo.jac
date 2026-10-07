import from model { build }
import from jaclang.lib.tensor_graph { Compute }
import torch;
import os;

with entry {
    torch.set_num_threads(1);
    with torch.inference_mode() {
        tg = build();
        feeds = {"source": torch.tensor([3, 4, 5, 2]), "target": torch.tensor([1, 6, 7])};
        run = tg spawn Compute(values=feeds, capture=["dec_attn.probabilities", "enc_norm2"]);
        fx = tg.compile(feeds, capture=["dec_attn.probabilities", "enc_norm2"]);
        lowered = fx(feeds);
        torch.testing.assert_close(run.output, lowered.output);
        print("library Compute:", len(run.trace), "nodes;", len(run.deliveries), "tensor edges");
        print("probabilities:", run.output.shape, "FX parity: passed");
        tg.export_dot(os.path.join(os.path.dirname(__file__), "graph.dot"));
        fx.export(os.path.join(os.path.dirname(__file__), "graph_fx.py"));
    }
}
