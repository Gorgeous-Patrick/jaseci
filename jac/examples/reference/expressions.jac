# Expressions - Ternary conditional expressions

with entry {
    # Ternary expression (condition ? true_value : false_value)
    x = 1 if 5 / 2 == 1 else 2;
    print(x);

    # More complex ternary expressions
    age = 20;
    status = "adult" if age >= 18 else "minor";
    print(status);

    # Nested ternary
    score = 85;
    grade = "A" if score >= 90 else ("B" if score >= 80 else "C");
    print(grade);

    # Ternary with function calls
    value = max(10, 20) if True else min(10, 20);
    print(value);
}
