# Atomic expressions - Atomic forward pipe operator

with entry {
    # Atomic forward pipe :> (passes value to next function atomically)
    "Hello world!" :> print;

    # Chained atomic pipes
    "Welcome" :> type :> print;

    # Atomic pipe for cleaner function composition
    result = 5 :> (lambda x: int : x * 2) :> (lambda x: int : x + 10);
    print(result);
}
