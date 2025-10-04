# Enumerations

import from enum { unique }

# Enum with decorator and SEMI (forward declaration)
@unique
enum Color;

# Impl for enum (using enum_block structure)
impl Color {
    RED = 1,
    GREEN = 2,
    BLUE = 3
}

# Enum with access tag and enum_block
enum :protect Role {
    ADMIN = 'admin',
    USER = 'user',
    GUEST = 'guest'

    # Free code in enum_block
    with entry {
        print('Initializing role system..');
        def foo -> str {
            return 'Accessing privileged Data';
        }
    }
}

# Enum with trailing comma in assignment_list
enum Status {
    PENDING = 0,
    ACTIVE = 1,
    INACTIVE = 2,
}

# Enum with python code block
enum Priority {
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3

    ::py::
    def get_priority_name(self):
        return self.name.lower()
    ::py::
}

# Enum with inherited archetypes (if supported)
# class BaseEnum {}
# enum ExtendedColor(BaseEnum) {
#     CYAN = 4,
#     MAGENTA = 5
# }

with entry {
    print(Color.RED.value, Role.foo());
    print(Status.ACTIVE);
}
