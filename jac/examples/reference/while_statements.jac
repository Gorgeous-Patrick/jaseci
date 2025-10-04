# While statements

with entry {
    # Basic while loop
    x = 0;
    while x < 5 {
        print(x);
        x += 1;
    }

    # While with else clause (executed when condition becomes false)
    count = 0;
    while count < 3 {
        print(f"Count: {count}");
        count += 1;
    } else {
        print("While loop completed normally");
    }

    # While with break (else won't execute)
    i = 0;
    while i < 10 {
        if i == 5 {
            break;
        }
        print(f"i = {i}");
        i += 1;
    } else {
        print("This won't print because of break");
    }
}
