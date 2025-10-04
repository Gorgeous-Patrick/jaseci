# Arithmetic expressions

with entry {
    p = print;

    # Basic arithmetic operations
    p("Multiply:", 7 * 2);
    p("Division:", 15 / 3);
    p("Floor division:", 15 // 3);
    p("Modulo:", 17 % 5);
    p("Exponentiation:", 2 ** 3);
    p("Addition:", 9 + 2);
    p("Subtraction:", 9 - 2);

    # Combined operations
    p("Combo:", (9 + 2) * 9 - 2);

    # Unary operations (factor)
    x = 5;
    p("Unary plus:", +x);
    p("Unary minus:", -x);
    p("Bitwise NOT:", ~x);

    # Power precedence
    p("2 ** 3 ** 2 =", 2 ** 3 ** 2);  # Right associative

    # Matrix multiplication operator @ (DECOR_OP in term)
    # Note: This requires matrix types
    # matrix1 @ matrix2

    # Complex expression
    result = 2 + 3 * 4 ** 2 - 10 / 2;
    p("Complex:", result);

    # Chained arithmetic
    p("Chain:", 100 - 50 + 25);
    p("Chain mult:", 2 * 3 * 4);

    # Modulo and division together
    p("17 // 5 =", 17 // 5);
    p("17 % 5 =", 17 % 5);
}
