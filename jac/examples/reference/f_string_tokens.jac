# F-string tokens

with entry {
    x = "a";
    y = 25;

    # Double-quoted f-string with interpolation
    print(f"Hello {x} {y} {{This is an escaped curly brace}}");

    # Single-quoted f-string
    print(f'Single quoted: {x} and {y}');

    # F-string with dictionary access
    person = {"name":"Jane", "age":25 };
    print(f"Hello, {person['name']}! You're {person['age']} years old.");

    # F-string with escaped braces (FSTR_BESC)
    print(f"Escaped braces: {{{{ and }}}}");

    # F-string with expression
    print(f"Calculation: {5 + 3} = {5 + 3}");

    # F-string with method calls
    text = "hello";
    print(f"Uppercase: {text.upper()}");

    # F-string with conditional
    age = 18;
    print(f"Status: {('Adult' if age >= 18 else 'Minor')}");

    # Multi-line f-string
    name = "Alice";
    score = 95;
    message = f"""
    Name: {name}
    Score: {score}
    Grade: {('A' if score >= 90 else 'B')}
    """;
    print(message);

    # F-string with escape sequences
    print("This is the first line.\n This is the second line.");
    print("This will not print.\r This will be printed");
    print("This is \t tabbed.");
    print("Line 1\fLine 2");

    # F-string with join
    words = ["Hello", "World!", "I", "am", "a", "Jactastic!"];
    print(f"{'\n'.join(words)}");

    # Nested f-strings
    value = 42;
    print(f"Value is {f'{value}'}");

    # F-string with format specifiers (if supported)
    pi = 3.14159;
    # print(f"Pi to 2 decimals: {pi:.2f}");
}
