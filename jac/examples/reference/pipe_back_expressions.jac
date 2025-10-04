# Pipe back expressions

def double(x: int) -> int {
    return (x * 2);
}

def triple(x: int) -> int {
    return x * 3;
}

def negate(x: int) -> int {
    return -x;
}

with entry {
    # Basic backward pipe
    number = 5;
    result = double <| number;
    print(result);

    # TODO: Fix Chained backward pipes (right to left evaluation)
    # value = 2;
    # chained = negate <| triple <| double <| value;
    # print(f"2 <- double <- triple <- negate = {chained}");

    # Backward pipe with lambda
    x = (lambda n:int : n * 3) <| 10;
    print(x);

    # Backward pipe to function calls
    data = sum <| [1, 2, 3, 4, 5];
    print(f"Sum: {data}");
}
