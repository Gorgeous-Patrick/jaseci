edge Follow {}
node Person { has name: str; }

with entry {
    # Create a simple graph
    p1 = Person(name="Alice");
    root +>: Follow :+> p1;
    
    print("=== ORIGINAL EDGE ===");
    orig_edge = root.__jac__.edges[0];
    print(f"Edge type: {type(orig_edge.archetype).__name__}");
    print(f"Edge is populated: {orig_edge.is_populated()}");
    print(f"Target: {orig_edge.target.archetype.name if hasattr(orig_edge.target.archetype, 'name') else 'No name'}");
    
    print("\n=== CREATING STUB ===");
    stub = orig_edge.make_stub();
    print(f"Stub type: {type(stub).__name__}");
    print(f"Stub is populated: {stub.is_populated()}");
    print(f"Stub arch_cls: {stub.__dict__.get('arch_cls', 'NOT SET')}");
    
    # Try to access stub's target
    print("\n=== ACCESSING STUB TARGET ===");
    try {
        print(f"Stub target type: {type(stub.target).__name__}");
        print(f"Stub target is populated: {stub.target.is_populated()}");
        # This should trigger populate
        target_name = stub.target.archetype.name;
        print(f"Target name after access: {target_name}");
    } except Exception as e {
        print(f"Error accessing stub target: {e}");
    }
}
