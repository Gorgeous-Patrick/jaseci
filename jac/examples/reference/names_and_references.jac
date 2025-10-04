# Names and references

obj Animal {
    has species: str;
    has sound: str;

    # init special ref
    def init(species: str, sound: str) {
        self.species = species;
        self.sound = sound;
    }
}

obj Dog(Animal) {
    has breed: str;
    has trick: str by postinit;

    # postinit special ref
    def postinit {
        self.trick = "Roll over";
        print("Postinit called");
    }

    # self special ref
    def speak {
        print(f"{self.species} says {self.sound}");
    }

    # super special ref
    def init(breed: str) {
        super.init(species="Dog", sound="Woof!");
        self.breed = breed;
    }
}

obj Cat(Animal) {
    def init(fur_color: str) {
        # super special ref
        super.init(species="Cat", sound="Meow!");
        self.fur_color = fur_color;
    }
}

# Walker with here and visitor special refs
walker Explorer {
    can explore with `root entry {
        # here special ref - current node
        print(f"Current node (here): {here}");

        # visitor special ref - current walker
        print(f"Current walker (visitor): {visitor}");

        # root special ref - root node
        print(f"Root node: {root}");

        visit [-->];
    }
}

node Location {
    has name: str;

    can greet with Explorer entry {
        # here refers to current node in spatial context
        print(f"At location: {here.name}");
    }
}

# Keyword escape with <>
# obj <>class {}  # KWESC_NAME - escapes keyword 'class'
# <>for = 10;     # Using 'for' as variable name

with entry {
    dog = Dog(breed="Labrador");
    cat = Cat(fur_color="Tabby");

    # TODO: Fix something wrong here with dog.trick
    # print(dog.breed, dog.sound, dog.trick);
    dog.speak();

    # root special ref in graph context
    # root is available in spatial/graph contexts

    # Demonstrate walker special refs
    # loc1 = Location(name="City");
    # root ++> loc1;
    # root spawn Explorer();
}
