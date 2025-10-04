# Assignments

with entry {
    # Chain assignment (multiple =)
    a = b = 16;
    print(a, b);

    # Let assignment
    let c = 18;
    print(c);

    # Type annotation with value
    x: int = 42;
    print(x);

    # Type annotation without value
    y: str;
    y = "hello";
    print(y);

    # Augmented assignments - all operators
    a >>= 2;  # Right shift assign
    print(a);

    a <<= 2;  # Left shift assign
    print(a);

    c //= 4;  # Floor division assign
    print(c);

    num = 10;
    num += 5;   # Add assign
    num -= 3;   # Subtract assign
    num *= 2;   # Multiply assign
    num /= 2;   # Division assign
    num %= 3;   # Modulo assign
    num **= 2;  # Power assign

    bits = 15;
    bits &= 7;   # Bitwise AND assign
    bits |= 8;   # Bitwise OR assign
    bits ^= 3;   # Bitwise XOR assign

    # Matrix multiplication assign (if supported)
    # matrix @= other_matrix;

    # Yield expression on right side of assignment
    def gen() {
        yield 1;
        yield 2;
    }

    # g = (yield from gen());  # Yield expr in assignment

    # Multiple chain assignments
    x = y = z = 100;
    print(x, y, z);

    # Assignment with expression
    result = 5 * (3 + 2);
    print(result);
}
