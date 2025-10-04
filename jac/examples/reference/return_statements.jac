# Return statements

def foo -> int{
    a = 42;
    return a;
}

def bar {
    print("Executing bar");
    # Return without expression (returns None)
    return;
}

def get_value(x: int) -> int {
    if x > 0 {
        return x * 2;
    } else {
        return 0;
    }
}

def early_return(flag: bool) {
    if flag {
        return;  # Early return
    }
    print("This won't execute if flag is True");
}

with entry {
    print("Returned:", foo());
    bar();
    print("get_value(5):", get_value(5));
    print("get_value(-3):", get_value(-3));
    early_return(True);
    early_return(False);
}
