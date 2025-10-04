# Functions and Abilities

obj Divider {
    # Basic function with parameters and return type
    def divide(x: float, y: float) -> float {
        return (x / y);
    }

    # Function with only return hint (no params)
    def get_default_divisor -> float {
        return 1.0;
    }
}

# Abstract class with abstract method
obj Calculator {
    # Static function with access tag
    static def:priv multiply(a: float, b: float) -> float {
        return a * b;
    }

    # Abstract method (forward declaration with abs)
    def substract -> float abs;

    # Forward declaration with params and variadic args
    def add(number: float, *a: tuple) -> float;

    # Function with **kwargs
    def configure(**options: dict) -> dict;

    # Function with positional-only params (DIV separator)
    # def divide_strict(x: float, y: float, /) -> float;

    # Function with keyword-only params (STAR_MUL separator)
    # def compute(x: float, *, precision: int = 2) -> float;

    # Override keyword
    # override def parent_method -> str {
    #     return "overridden";
    # }
}

obj Substractor(Calculator) {
    def substract(x: float, y: float) -> float {
        return (x - y);
    }
}

# Impl for function
impl Calculator.add
(number: float, *a: tuple) -> float {
    return (number * sum(a));
}

# Walker with abilities (can statements)
walker TaskRunner {
    # Ability with entry event
    can initialize with entry {
        print("Walker entered");
    }

    # Ability with exit event
    can cleanup with exit {
        print("Walker exiting");
    }

    # Ability with expression (no entry/exit specified)
    # can process with node_obj entry {
    #     print("Processing node");
    # }
}

# Async function
async def fetch_data(url: str) -> dict {
    return {"data": "fetched"};
}

# Async ability
walker AsyncWalker {
    async can process with entry {
        print("Async processing");
    }
}

# Function with decorator
def logger(func: object) {
    return func;
}

@logger
def logged_function(x: int) -> int {
    return x * 2;
}

# Function with 'by expression' tail
# def proxy_func by some_other_func;

# Abstract ability
walker AbstractWalker {
    can must_implement with entry abs;
}

with entry {
    div = Divider();
    sub = Substractor();
    print(div.divide(55, 11));
    print(Calculator.multiply(9, -2));
    print(sub.add(5, 20, 34, 56));
    print(sub.substract(9, -2));
}
