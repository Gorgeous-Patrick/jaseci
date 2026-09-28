"""Operations that must retain their host semantics and be rejected for now."""

glob scale: float = 2.0;

def float_div(a: float, b: float) -> float {
    return a / b;
}

def float_mod(a: float, b: float) -> float {
    return a % b;
}

def float_floor_div(a: float, b: float) -> float {
    return a // b;
}

def float_pow(a: float, b: float) -> float {
    return a ** b;
}

def int_add(a: int, b: int) -> int {
    return a + b;
}

def global_read(a: float) -> float {
    return a * scale;
}

def helper_div(a: float, b: float) -> float {
    return float_div(a, b);
}

def recursive(a: float) -> float {
    if a > 0.0 {
        return recursive(a - 1.0);
    }
    return a;
}

def with_output(a: float) -> float {
    print(a);
    return a;
}
