edge Follow {}
edge CloseFriend(Follow) {}
node Person { has name: str; }
node VIPPerson(Person) { has tier: str = "gold"; }

with entry {
    # Build simple graph
    p1 = Person(name="Alice");
    p2 = VIPPerson(name="Bob");
    root +>: Follow :+> p1;
    root +>: CloseFriend :+> p2;
    
    # Test without stubs first
    print("WITHOUT STUBS:");
    result1 = [root->:Follow:->];
    print(f"Follow filter result count: {len(result1)}");
    for node in result1 {
        print(f"  - {node.name}");
    }
    
    # Now with stubs
    root_anch = root.__jac__;
    orig_edges = list(root_anch.edges);
    stub_edges = [e.make_stub() for e in orig_edges];
    root_anch.edges = stub_edges;
    
    print("\nWITH STUBS:");
    result2 = [root->:Follow:->];
    print(f"Follow filter result count: {len(result2)}");
    for node in result2 {
        print(f"  - {node.name}");
    }
}
