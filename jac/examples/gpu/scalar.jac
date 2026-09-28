"""Export these functions with jac build --as ptx --gpu-entry FUNCTION.

Each kernel applies one function independently to the elements of input arrays.
The build emits PTX; a CUDA host launcher is not included yet.
"""

def multiply_add(a: float, b: float, c: float) -> float {
    return a * b + c;
}

def within_radius(x: float, y: float, radius: float) -> bool {
    return x * x + y * y <= radius * radius;
}

def squared_difference(a: float, b: float) -> float {
    delta = a - b;
    return delta * delta;
}

def distance_squared(ax: float, ay: float, bx: float, other_y: float) -> float {
    return squared_difference(ax, bx) + squared_difference(ay, other_y);
}
