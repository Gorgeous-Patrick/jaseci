# Archetypes - Core Jac archetype declarations

def print_base_classes(cls: type) -> type {
    print(
        f"Base classes of {cls.__name__}: {[c.__name__ for c in cls.__bases__]}"
    );
    return cls;
}

# Class archetype (basic)
class Animal {}

# Object archetype (basic)
obj Domesticated {}

# Node archetype with inheritance and decorator
@print_base_classes
node Pet(Animal, Domesticated) {}

# Edge archetype (connects nodes in spatial graphs)
edge Relationship {}

# Edge with access tag
edge :pub Connection {}

# Walker archetypes with inheritance
walker Person(Animal) {}

walker Feeder(Person) {}

@print_base_classes
walker Zoologist(Feeder) {}

# Async walker
async walker MyWalker {}

# Archetype with access tags (visibility modifiers)
obj :priv PrivateObject {}
obj :pub PublicObject {}
obj :protect ProtectedObject {}

# Archetype with SEMI (forward declaration)
class ForwardDeclared;
node AbstractNode;

impl ForwardDeclared {
    def info {
        print("This is a forward-declared class.");
    }
}

impl AbstractNode {
    def info {
        print("This is an abstract node.");
    }
}

# Async applied to other archetypes (if supported)
# async obj AsyncObject {}
