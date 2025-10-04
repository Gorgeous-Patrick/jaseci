# Archetype bodies - Member statements and structures

# Docstring for member
"This is a member docstring"
obj Car {


    # Has statements with type annotations
    has make: str,
        model: str,
        year: int;

    # Static has statement
    static has wheels: int = 4;

    # Has with access tag
    has :priv internal_id: str = "car_123";

    # Let instead of has
    let manufacturer: str = "Unknown";

    # Has with by postinit
    has config: dict by postinit;

    def postinit {
        self.config = {"color": "white", "sunroof": False};
    }

    # Methods in body
    def display_car_info {
        print(f"Car Info: {self.year} {self.make} {self.model}");
    }

    static def get_wheels -> int {
        return Car.wheels;
    }

    # Python code block in member
    ::py::
    def python_method(self):
        return "This is Python code"
    ::py::

    # Nested archetype
    class Engine {
        has horsepower: int;
    }

    # Free code in member (with entry)
    with entry {
        print("Member-level entry");
    }
}

with entry {
    car = Car("Toyota", "Camry", 2020);
    car.display_car_info();
    print("Number of wheels:", Car.get_wheels());
}
