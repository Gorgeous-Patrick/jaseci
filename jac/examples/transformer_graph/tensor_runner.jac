import from model { build, greedy }
import tensor_experiments;
import os;

with entry {
    tensor_experiments.main(build, greedy, os.path.dirname(__file__));
}
