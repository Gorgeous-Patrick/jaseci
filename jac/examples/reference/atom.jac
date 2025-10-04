# Atom - Atomic expressions and literals

impl x {
    aa=67,
    y="aaa" + f"b{aa}bbcc"
}

glob c = (3, 4, 5), list1 = [2, 3, 4, 5];

with entry {
    # String literals
    a = "abcde....";
    print("String:", a);

    # Bool literal
    b = True;
    c = False;
    print("Bool:", b, c);

    # NULL literal
    n = None;
    print("None:", n);

    # Integer literals
    decimal = 42;
    print("Decimal int:", decimal);

    # Binary literal
    binary = 0b1100;
    print("Binary 0b1100:", binary);

    # Octal literal
    octal = 0o755;
    print("Octal 0o755:", octal);

    # Hexadecimal literal
    hexadecimal = 0xFF;
    print("Hex 0xFF:", hexadecimal);

    # Float literals
    float_val = 3.14;
    scientific = 1.5e10;
    print("Float:", float_val, scientific);

    # ELLIPSIS literal
    ellipsis = ...;
    print("Ellipsis:", ellipsis);

    # Parenthesized expression
    result = (5 + 3) * 2;
    print("Parenthesized:", result);

    # Parenthesized yield expression
    # def gen() {
    #     val = (yield 10);
    # }

    # named_ref standalone
    variable_name = 100;
    print("Named ref:", variable_name);

    # Type reference with backtick
    # type_str = `str;
    # type_int = `int;
    # print("Type refs:", type_str, type_int);

    # Builtin type as value
    string_type = str;
    int_type = int;
    print("Builtin types:", string_type, int_type);

    # Collections (atom_collection)
    tuple_val = (1, 2, 3);
    list_val = [1, 2, 3];
    dict_val = {"key": "value"};
    set_val = {1, 2, 3};

    # Multistring (concatenated strings)
    multistr = "Hello " "World";
    print("Multistring:", multistr);

    # F-string
    name = "Alice";
    fstr = f"Hello {name}";
    print("F-string:", fstr);

    enum x;
    print(x.y.value);
}
