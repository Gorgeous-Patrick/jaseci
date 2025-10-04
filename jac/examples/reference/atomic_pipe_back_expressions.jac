# Atomic pipe back expressions - Atomic backward pipe operator

with entry {
    # Atomic backward pipe <: (right to left flow)
    print <: "Hello world!";

    # Complex atomic pipe back example
    a = [2, 4, 5, 7, 8];
    b = [4, 8, 9, 13, 20];

    # Chained atomic backward pipes
    c = len <: a + b :> len;
    print(c);

    # Backward atomic pipe with lambda
    result = (lambda x:int : x * 3) <: 10;
    print("Result:", result);
}
