edge Follow {}
edge CloseFriend(Follow) {}
node Person { has name: str; }
node VIPPerson(Person) { has tier: str = "gold"; }

with entry {
    # Build simple graph
    p1 = Person(name="Alice");
    p2 = VIPPerson(name="Bob");
    
    print(f"BEFORE EDGE CREATION:");
    print(f"Root edges: {len(root.__jac__.edges)}");
    print(f"P1 edges: {len(p1.__jac__.edges)}");
    print(f"P2 edges: {len(p2.__jac__.edges)}");
    
    root +>: Follow :+> p1;
    
    print(f"\nAFTER FIRST EDGE:");
    print(f"Root edges: {len(root.__jac__.edges)}");
    print(f"P1 edges: {len(p1.__jac__.edges)}");
    
    root +>: CloseFriend :+> p2;
    
    print(f"\nAFTER SECOND EDGE:");
    print(f"Root edges: {len(root.__jac__.edges)}");
    print(f"P2 edges: {len(p2.__jac__.edges)}");
    
    # Check edge details
    print(f"\nEDGE DETAILS:");
    i = 0;
    for edge in root.__jac__.edges {
        print(f"Edge {i}: {type(edge.archetype).__name__}");
        i += 1;
    }
}
