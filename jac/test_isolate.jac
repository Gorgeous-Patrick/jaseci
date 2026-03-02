node Person { has name: str; }

glob isolated_edges = [];

with entry {
    print("=== TEST 1: Check initial state ===");
    print(f"Root edges at start: {len(root.__jac__.edges)}");
    print(f"Root ID: {root.__jac__.id}");
    
    # Store initial edges
    for e in root.__jac__.edges {
        isolated_edges.append(str(type(e.archetype).__name__));
    }
    
    print(f"Initial edge types: {isolated_edges}");
}
