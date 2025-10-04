# Raise statements

def foo(value: int) {
    if value < 0 {
        raise ValueError("Value must be non-negative");
    }
}

def bar(x: int) {
    try {
        result = 10 / x;
    } except ZeroDivisionError as e {
        # Raise from - chain exceptions
        raise RuntimeError("Division failed") from e;
    }
}

def reraise_example {
    try {
        raise ValueError("Original error");
    } except ValueError {
        print("Caught error, re-raising...");
        # Bare raise - re-raises the current exception
        raise;
    }
}

def conditional_raise(value: any) {
    if value is None {
        raise ValueError("Value cannot be None");
    }
    if not isinstance(value, int) {
        raise TypeError(f"Expected int, got {type(value).__name__}");
    }
    return value * 2;
}

with entry {
    # Basic raise
    try  {
        foo(-1);
    } except ValueError as e  {
        print("Raised:", e);
    }

    # Raise from (exception chaining)
    try {
        bar(0);
    } except RuntimeError as e {
        print("Runtime error:", e);
        # print("Caused by:", e.__cause__);
    }

    # Bare raise (re-raise)
    try {
        reraise_example();
    } except ValueError as e {
        print("Re-raised:", e);
    }

    # Conditional raise
    try {
        conditional_raise(None);
    } except ValueError as e {
        print("None value error:", e);
    }

    try {
        conditional_raise("not an int");
    } except TypeError as e {
        print("Type error:", e);
    }
}
