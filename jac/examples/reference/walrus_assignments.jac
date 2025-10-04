# Walrus assignments

with entry {
    # Walrus operator in if condition
    a = 5;
    if (b := a + a // 2) > 5 {
        print("b is greater than 5");
        print(f"b = {b}");
    }

    # Walrus in while loop
    data = [1, 2, 3, 4, 5];
    i = 0;
    while (item := data[i] if i < len(data) else None) {
        print(f"Item: {item}");
        i += 1;
        if i >= 3 {
            break;
        }
    }

    # Walrus in list comprehension
    values = [1, 2, 3, 4, 5];
    # results = [y for x in values if (y := x * 2) > 4];
    # print(results);

    # Walrus in expression
    result = (x := 10) + 5;
    print(f"x = {x}, result = {result}");

    # Multiple walrus assignments
    if (m := 5) and (n := 10) {
        print(f"m = {m}, n = {n}");
    }
}
