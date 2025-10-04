# Yield statements

def myFunc {
    yield "Hello";
    yield 91;
    yield "Good Bye";
    yield ;  # Yield without expression (yields None)
}

def number_generator(n: int) {
    for i in range(n) {
        yield i;
    }
}

def yield_from_example {
    # Yield from another generator (delegates to sub-generator)
    yield from number_generator(3);
    yield from ["a", "b", "c"];
}

def conditional_yield(items: list) {
    for item in items {
        if item % 2 == 0 {
            yield item;
        }
    }
}

with entry {
    # Basic yield usage
    x = myFunc();
    for z in x {
        print(z);
    }

    # Yield from example
    print("\nYield from:");
    gen = yield_from_example();
    for val in gen {
        print(val);
    }

    # Conditional yield
    print("\nEven numbers:");
    evens = conditional_yield([1, 2, 3, 4, 5, 6]);
    for num in evens {
        print(num);
    }
}
