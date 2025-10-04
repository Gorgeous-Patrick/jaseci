# Visit statements

walker Visitor {
    can travel with `root entry {
        # Visit with edge reference and else clause
        visit [-->] else {
            visit root;
            disengage;
        }
    }
}

walker TypedVisitor {
    can explore with `root entry {
        # Visit with type hint (typed expression in colons)
        # visit :node: [-->];

        # Visit without else, terminating with SEMI
        visit [-->];
    }
}

walker ConditionalVisitor {
    has count: int = 0;

    can check with `root entry {
        # Visit with expression but no edge
        visit root;

        # Conditional visit
        if self.count < 5 {
            visit [-->];
            self.count += 1;
        }
    }
}

node item {
    can speak with Visitor entry {
        print("Hey There!!!");
    }
}

node Person {
    has name: str;

    can greet with TypedVisitor entry {
        print(f"Hello from {self.name}");
    }
}

with entry {
    # Build graph
    for i=0 to i<5 by i+=1  {
        root ++> item();
    }

    # Spawn walker
    root spawn Visitor();

    # Visit statement variations demonstrated in walker abilities
}
