edge Follow {}
edge CloseFriend(Follow) {}
node Person { has name: str; }
node VIPPerson(Person) { has tier: str = "gold"; }

with entry {
    # Clean test - create fresh graph
    p1 = Person(name="Alice");
    p2 = VIPPerson(name="Bob");
    
    print("=== BEFORE CREATING ANY EDGES ===");
    print(f"Root edges: {len(root.__jac__.edges)}");
    print(f"P1 edges: {len(p1.__jac__.edges)}");
    print(f"P2 edges: {len(p2.__jac__.edges)}");
    
    # Create edges explicitly
    root +>: Follow :+> p1;
    root +>: CloseFriend :+> p2;
    
    print("\n=== AFTER CREATING EDGES ===");
    print(f"Root edges: {len(root.__jac__.edges)}");
    print(f"P1 edges: {len(p1.__jac__.edges)}");
    print(f"P2 edges: {len(p2.__jac__.edges)}");
    
    # Check what edges exist
    print("\n=== ROOT EDGE DETAILS ===");
    for edge in root.__jac__.edges {
        edge_type = type(edge.archetype).__name__;
        source_type = type(edge.source.archetype).__name__ if edge.source else "None";
        target_type = type(edge.target.archetype).__name__ if edge.target else "None";
        print(f"Edge: {edge_type}, Source: {source_type}, Target: {target_type}");
    }
    
    # Test traversal without stubs
    print("\n=== TRAVERSAL WITHOUT STUBS ===");
    follow_nodes = [root->:Follow:->];
    print(f"Follow traversal result: {len(follow_nodes)} nodes");
    for node in follow_nodes {
        print(f"  - {node.name}");
    }
    
    # Convert to stubs and test again
    print("\n=== CONVERTING TO STUBS ===");
    root_anch = root.__jac__;
    orig_edges = list(root_anch.edges);
    stub_edges = [e.make_stub() for e in orig_edges];
    root_anch.edges = stub_edges;
    
    print(f"Root now has {len(root_anch.edges)} stub edges");
    
    # Test traversal with stubs
    print("\n=== TRAVERSAL WITH STUBS ===");
    follow_nodes_stub = [root->:Follow:->];
    print(f"Follow traversal result: {len(follow_nodes_stub)} nodes");
    for node in follow_nodes_stub {
        print(f"  - {node.name}");
    }
}
