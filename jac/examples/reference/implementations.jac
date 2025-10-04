# Implementations - Forward declarations and implementations

# Forward declarations
def foo -> str;

obj vehicle;

enum Size;

# Implementation of function
impl foo -> str {
    return ("Hello");
}

# Implementation of object
impl vehicle  {
    has name: str = "Car";
}

# Implementation of enum
impl Size {
    Small=1,
    Medium=2,
    Large=3
}

with entry {
    car = vehicle();
    print(foo());
    print(car.name);
    print(Size.Medium.value);
}
