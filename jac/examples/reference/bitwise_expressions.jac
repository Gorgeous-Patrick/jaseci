# Bitwise expressions - Bitwise operators for binary operations

with entry {
    p = print;

    # Bitwise AND (&)
    p("5 & 3 =", 5 & 3);  # 101 & 011 = 001 = 1

    # Bitwise OR (|)
    p("5 | 3 =", 5 | 3);  # 101 | 011 = 111 = 7

    # Bitwise XOR (^)
    p("5 ^ 3 =", 5 ^ 3);  # 101 ^ 011 = 110 = 6

    # Bitwise NOT (~)
    p("~5 =", ~5);  # ~101 = -6 (two's complement)

    # Left shift (<<)
    p("5 << 1 =", 5 << 1);  # 101 << 1 = 1010 = 10

    # Right shift (>>)
    p("5 >> 1 =", 5 >> 1);  # 101 >> 1 = 10 = 2

    # Combined bitwise operations
    result = (8 | 4) & 12;
    p("(8 | 4) & 12 =", result);

    # Bitwise operations with variables
    a = 15;  # 1111
    b = 7;   # 0111
    p("15 & 7 =", a & b);
    p("15 | 7 =", a | b);
    p("15 ^ 7 =", a ^ b);
}
