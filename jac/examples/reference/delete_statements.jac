# Delete statements

with entry {
    # Delete list element
    x = [2, 4, 5, 7, 9];
    print("Before Delete:", x);
    del x[3];
    print("After Delete:", x);

    # Delete variable
    y = 100;
    print("y before delete:", y);
    del y;
    # print(y);  # Would raise NameError

    # Delete dictionary item
    d = {"a": 1, "b": 2, "c": 3};
    print("Dict before delete:", d);
    del d["b"];
    print("Dict after delete:", d);

    # Delete object attribute
    obj MyClass {
        has value: int = 42;
    }

    instance = MyClass();
    print("Attribute before delete:", instance.value);
    del instance.value;
    # print(instance.value);  # Would raise AttributeError

    # Delete multiple items
    lst = [1, 2, 3, 4, 5];
    del lst[1];  # Delete index 1
    del lst[2];  # Delete index 2 (which is now 4 after previous delete)
    print("After multiple deletes:", lst);

    # Delete slice
    numbers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    del numbers[2:5];
    print("After slice delete:", numbers);
}
