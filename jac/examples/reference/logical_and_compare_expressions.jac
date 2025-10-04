# Logical and compare expressions

with entry {
    # Comparison operators
    if 5 > 4 {
        print("5 > 4: True");
    }

    if 5 >= 5 {
        print("5 >= 5: True");
    }

    if 3 < 10 {
        print("3 < 10: True");
    }

    if 3 <= 3 {
        print("3 <= 3: True");
    }

    if 5 == 5 {
        print("5 == 5: True");
    }

    if "a" != "b" {
        print("'a' != 'b': True");
    }

    # Identity operators
    a = [1, 2, 3];
    b = [1, 2, 3];
    c = a;

    print("a is b:", a is b);  # False (different objects)
    print("a is c:", a is c);  # True (same object)
    print("a is not b:", a is not b);  # True

    # Membership operators
    print("3 in a:", 3 in a);  # True
    print("5 in a:", 5 in a);  # False
    print("5 not in a:", 5 not in a);  # True

    # Logical operators
    print("True or False:", True or False);
    print("True and False:", True and False);
    print("False and False:", False and False);

    # Logical NOT
    print("not True:", not True);
    print("not False:", not False);

    # Chained comparisons
    x = 15;
    if 10 < x < 20 {
        print("x is between 10 and 20");
    }

    if 0 <= x <= 100 {
        print("x is between 0 and 100 inclusive");
    }

    # Complex logical expressions
    age = 25;
    has_license = True;

    if age >= 18 and has_license {
        print("Can drive");
    }

    if age < 18 or not has_license {
        print("Cannot drive");
    } else {
        print("Allowed to drive");
    }

    # Chained logical operations
    if True and True and True {
        print("All true");
    }

    if False or False or True {
        print("At least one true");
    }
}
