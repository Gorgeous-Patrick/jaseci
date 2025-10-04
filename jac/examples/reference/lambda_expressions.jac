# Lambda expressions

with entry {
    # Lambda with parameters and return hint
    x = lambda a: int, b: int -> int : b + a;
    print(x(5, 4));

    # Lambda without parameters
    get_five = lambda : 5;
    print(get_five());

    # Lambda without return hint
    add = lambda x: int, y: int : x + y;
    print(add(3, 7));

    # Lambda with only return hint (no params)
    get_default = lambda -> int : 42;
    print(get_default());

    # Lambda with default parameter values
    multiply = lambda x: int = 2, y: int = 3 : x * y;
    print(multiply());
    print(multiply(5));
    print(multiply(5, 10));

    # Lambda with variadic args (use regular function instead)
    def sum_all(*args: tuple) { return sum(args); }
    print(sum_all(1, 2, 3, 4, 5));

    # Lambda as argument to function
    numbers = [1, 2, 3, 4, 5];
    squared = list(map(lambda x: int : x ** 2, numbers));
    print(squared);

    # Lambda in filter
    evens = list(filter(lambda x: int : x % 2 == 0, numbers));
    print(evens);

    # Complex lambda with conditional expression
    max_val = lambda a: int, b: int : a if a > b else b;
    print(max_val(10, 20));
}
