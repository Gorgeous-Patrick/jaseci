# Builtin types

glob a: float = 9.2;

glob b: int = 44;

glob c: list = [2, 4, 6, 10];

glob d: dict = {'name':'john', 'age':28 };

glob e: tuple = ("jaseci", 5, 4, 14);

glob f: bool = True;

glob g: str = "Jaseci";

glob h: set = {5, 8, 12, "unique"};

# bytes type
glob i: bytes = b"binary data";

# any type (accepts any value)
glob j: any = "can be anything";

# type type (for type objects)
glob k: type = str;

with entry {
    print("float:", type(a), a);
    print("int:", type(b), b);
    print("list:", type(c), c);
    print("dict:", type(d), d);
    print("tuple:", type(e), e);
    print("bool:", type(f), f);
    print("str:", type(g), g);
    print("set:", type(h), h);
    print("bytes:", type(i), i);
    print("any:", type(j), j);
    print("type:", type(k), k);

    # Type annotations in function
    def typed_func(x: int, y: float, z: str) -> tuple {
        return (x, y, z);
    }

    result = typed_func(1, 2.5, "test");
    print("Typed function result:", result);

    # Variable annotations
    var1: list = [1, 2, 3];
    var2: dict = {};
    var3: set = {1, 2};
    var4: bytes = b"hello";
    var5: any = 42;
    var6: type = int;

    print("All types demonstrated");
}
