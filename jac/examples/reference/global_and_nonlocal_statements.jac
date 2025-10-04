# Global and nonlocal statements

glob x = "Jaclang ";

def outer_func -> None {
    # Global with single name
    global x;

    x = 'Jaclang is ';
    y = 'Awesome';
    z = 'Language';

    def inner_func -> tuple[str, str] {
        # Nonlocal with single name
        nonlocal y;

        y = "Fantastic";
        return (x, y);
    }

    print(x, y);
    print(inner_func());
}

# Multiple names in global statement
glob a = 1;
glob b = 2;
glob c = 3;

def modify_globals {
    # Global with multiple names
    global a, b, c;

    a = 10;
    b = 20;
    c = 30;
}

def nested_scope {
    var1 = "outer1";
    var2 = "outer2";
    var3 = "outer3";

    def inner {
        # Nonlocal with multiple names
        nonlocal var1, var2, var3;

        var1 = "inner1";
        var2 = "inner2";
        var3 = "inner3";
    }

    print("Before inner:", var1, var2, var3);
    inner();
    print("After inner:", var1, var2, var3);
}

with entry {
    outer_func();

    print("Before modify_globals:", a, b, c);
    modify_globals();
    print("After modify_globals:", a, b, c);

    nested_scope();
}
