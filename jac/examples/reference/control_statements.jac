# Control statements

with entry {
    # Break - exits the loop
    for i in range(9) {
        if i > 2 {
            print("loop is stopped!!");
            break;
        }
        print(i);
    }

    # Continue - skips to next iteration
    for j in "WIN" {
        if j == "W" {
            continue;
        }
        print(j);
    }

    # Skip - Jac-specific control flow (similar to continue but for walker traversal)
    # Note: skip is primarily used in walker contexts
    walker SkipWalker {
        can process with entry {
            # skip;  # Would skip current node/edge processing
        }
    }

    # Break in while loop
    count = 0;
    while True {
        count += 1;
        if count > 5 {
            break;
        }
        print(f"Count: {count}");
    }

    # Continue in while loop
    n = 0;
    while n < 10 {
        n += 1;
        if n % 2 == 0 {
            continue;  # Skip even numbers
        }
        print(f"Odd: {n}");
    }

    # Nested loops with break
    for x in range(3) {
        for y in range(3) {
            if x == y == 1 {
                print(f"Breaking at ({x}, {y})");
                break;
            }
            print(f"({x}, {y})");
        }
    }
}
