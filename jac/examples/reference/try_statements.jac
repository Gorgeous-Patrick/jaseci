# Try statements

with entry {
    # Basic try-except with exception type and as binding
    try  {
        print("Result", 5 / 0);
    } except Exception as e  {
        print(e);
    }

    # Multiple except clauses (except_list with multiple except_def)
    try {
        x = int("not a number");
    } except ValueError as ve {
        print("ValueError:", ve);
    } except TypeError as te {
        print("TypeError:", te);
    } except Exception as e {
        print("Other exception:", e);
    }

    # Try with else clause (executes if no exception)
    try {
        result = 10 / 2;
    } except ZeroDivisionError {
        print("Cannot divide by zero");
    } else {
        print("Division successful:", result);
    }

    # Try with finally clause (always executes)
    try {
        f = None;
        # f = open("file.txt");
    } except FileNotFoundError {
        print("File not found");
    } finally {
        print("Cleanup: finally always runs");
    }

    # Try with except, else, and finally all together
    try {
        data = [1, 2, 3];
        print(data[1]);
    } except IndexError as ie {
        print("Index error:", ie);
    } else {
        print("Access successful");
    } finally {
        print("Cleanup complete");
    }

    # TODO: Bare except (without exception type)
    # try {
    #     risky_operation = 1 / 1;
    # } except {
    #     print("Caught any exception");
    # }
}
