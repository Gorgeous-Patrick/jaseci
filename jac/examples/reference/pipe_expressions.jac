# Pipe expressions

def square(x: int) -> int {
    return (x ** 2);
}

def double(x: int) -> int {
    return x * 2;
}

def increment(x: int) -> int {
    return x + 1;
}

with entry {
    # Basic forward pipe
    number = 5;
    result = number |> square;
    print(result);

    # TODO: Fix Chained forward pipes
    # value = 3;
    # chained = value |> increment |> double |> square;
    # print(f"3 -> increment -> double -> square = {chained}");

    # Pipe with function calls
    data = [1, 2, 3, 4, 5];
    total = data |> sum;
    print(f"Sum: {total}");

    # Pipe to lambda
    x = 10 |> (lambda n: int : n * 3);
    print(x);
}
