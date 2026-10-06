import from model { build, greedy, VOCAB }
import math_cpu;
import os;

with entry {
    m = build();
    source = [3, 4, 5, 2];
    labels = [6, 7, 2];
    shifted = [1] + labels[:-1];
    run = m.forward(source, shifted);
    math_cpu.check_probs(run.probabilities, len(shifted), VOCAB);
    print("CPU Transformer: d_model=8, heads=2, d_ff=16, vocab=13, encoder=1, decoder=1");
    print("source:", source, "labels:", labels, "shifted target:", shifted);
    print("probability shape:", (len(run.probabilities), len(run.probabilities[0])));
    print("teacher-forced argmax:", [math_cpu.argmax(row) for row in run.probabilities]);
    print("walker trace:", run.trace);
    print("edge deliveries:", len(run.deliveries));
    print("greedy (includes BOS):", greedy(m, source));
    filename = os.path.join(os.path.dirname(__file__), "graph.dot");
    m.export_dot(filename);
    print("actual graph export:", filename);
}
