# Special comprehensions - Filter and assign comprehensions

import random;

obj TestObj {
    has x: int = random.randint(0, 15),
        y: int = random.randint(0, 15),
        z: int = random.randint(0, 15);
}

with entry {
    random.seed(42);
    apple = [];
    for i=0 to i<100 by i+=1  {
        apple.append(TestObj());
    }

    # Filter comprehension - filters objects based on conditions
    # Syntax: collection(?condition1, condition2, ...)
    print(apple(?x >= 0, x <= 15) == apple);
}

obj MyObj {
    has apple: int = 0,
        banana: int = 0;
}

with entry {
    x = MyObj();
    y = MyObj();

    # Assign comprehension - assigns values to object attributes
    # Syntax: collection(=attr1=val1, attr2=val2, ...)
    mvar = [x, y](=apple=5, banana=7);
    print(mvar);
}
