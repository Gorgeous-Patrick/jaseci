# Tuples and Jac tuples - Python tuples vs Jac named tuples

def foo(first: int, second: int) -> None {
    print(first, second);
}

with entry {
    # Python-style tuple with trailing comma
    val1 = (3, ) + (4, );
    val2 = (val1[0] * val1[1], val1[0] + val1[1]);

    # Jac-style named tuples with pipe operator
    # Named parameters in tuple syntax
    (second=val2[1], first=val2[0]) |> foo;
    (first=val2[0], second=val2[1]) |> foo;

    # Regular tuple
    simple_tuple = (1, 2, 3);
    print("Tuple:", simple_tuple);
}
