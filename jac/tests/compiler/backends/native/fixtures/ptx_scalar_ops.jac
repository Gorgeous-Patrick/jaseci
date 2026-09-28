"""Runtime-free scalar functions for the experimental Jac PTX backend."""

def float_add(a: float, b: float) -> float {
    return a + b;
}

def float_sub(a: float, b: float) -> float {
    return a - b;
}

def float_mul(a: float, b: float) -> float {
    return a * b;
}

def float_neg(a: float) -> float {
    return -a;
}

def float_pos(a: float) -> float {
    return +a;
}

def float_eq(a: float, b: float) -> bool {
    return a == b;
}

def float_ne(a: float, b: float) -> bool {
    return a != b;
}

def float_lt(a: float, b: float) -> bool {
    return a < b;
}

def float_le(a: float, b: float) -> bool {
    return a <= b;
}

def float_gt(a: float, b: float) -> bool {
    return a > b;
}

def float_ge(a: float, b: float) -> bool {
    return a >= b;
}

def bool_not(a: bool) -> bool {
    return not a;
}

def bool_and(a: bool, b: bool) -> bool {
    return a and b;
}

def bool_or(a: bool, b: bool) -> bool {
    return a or b;
}

def float_select(flag: bool, a: float, b: float) -> float {
    return a if flag else b;
}

def float_clamp(a: float, lower: float, upper: float) -> float {
    if a < lower {
        return lower;
    } elif a > upper {
        return upper;
    }
    return a;
}

def float_mul_add(a: float, b: float, c: float) -> float {
    return a * b + c;
}

def float_sum_steps(a: float, steps: float) -> float {
    total = 0.0;
    while steps > 0.0 {
        total += a;
        steps -= 1.0;
    }
    return total;
}

def squared_difference(a: float, b: float) -> float {
    delta = float_sub(a, b);
    return float_mul(delta, delta);
}

def squared_distance(ax: float, ay: float, bx: float, other_y: float) -> float {
    return float_add(squared_difference(ax, bx), squared_difference(ay, other_y));
}
