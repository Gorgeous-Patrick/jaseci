import from model { build, greedy }
import torch;
import os;
import json;

with entry {
    torch.set_num_threads(1);
    with torch.inference_mode() {
        m = build();
        m.analyze([3, 4, 5, 2], [1, 6, 7]);
        run = m.forward([3, 4, 5, 2], [1, 6, 7], ["dec_attn.probabilities", "enc_norm2"]);
        print("labels [6,7,2]; shifted input [BOS=1,6,7]");
        print("operation nodes:", len(m.ops), "tensor edges:", len(m.topology()));
        print("output:", run.probabilities.shape, "trace:", len(run.trace));
        print("logical peak bytes:", m.plan["liveness"]["peak_logical_bytes"]);
        m.export_dot(os.path.join(os.path.dirname(__file__), "graph.dot"));
        m.export_analysis(os.path.join(os.path.dirname(__file__), "analysis.json"));
        with open(os.path.join(os.path.dirname(__file__), "execution.json"), "w") as f {
            json.dump({"trace": run.trace, "deliveries": run.deliveries, "handle_identity": run.handle_identity, "lifetime_trace": run.lifetime_trace}, f, indent=2);
        }
        print("greedy including BOS:", greedy(m, [3, 4, 5, 2]));
    }
}
