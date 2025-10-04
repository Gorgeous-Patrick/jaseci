# Free code - Top-level executable code blocks

import math;

obj circle {
    def init(radius: float) {
        self.radius = radius;
    }

    def area -> float {
        return math.pi * self.radius * self.radius;
    }
}

def foo(n_1: float) {
    return n_1 ** 2;
}

# Free code with entry - executes at module level
with entry {
    print("Hello World!");
    print(foo(7));
    print(int(circle(10).area()));
}
