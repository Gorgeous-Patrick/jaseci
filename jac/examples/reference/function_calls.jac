# Function calls - Various function call patterns

def foo(x: int, y: int, z: int) {
    return (x * y, y * z);
}

with entry {
    a = 5;

    # Function call with keyword arguments and expressions
    output = foo(x=4, y=4 if a % 3 == 2 else 3, z=9);
    print(output);

    # Positional arguments
    result = foo(1, 2, 3);
    print(result);

    # Mixed positional and keyword arguments
    mixed = foo(1, y=2, z=3);
    print(mixed);
}
