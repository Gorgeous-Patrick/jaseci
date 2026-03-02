import from jaclang.jac0core.runtime { is_arch_cls_compatible }

edge Follow {}
edge CloseFriend(Follow) {}
node Person { has name: str; }
node VIPPerson(Person) { has tier: str = "gold"; }

with entry {
    # Create a simple, controlled graph
    p1 = Person(name="Alice");
    p2 = VIPPerson(name="Bob");
    
    # Create ONLY these edges
    root +>: Follow :+> p1;
    root +>: CloseFriend :+> p2;
    
    print("=== GRAPH STRUCTURE ===");
    print(f"Root has {len(root.__jac__.edges)} edges");
    
    # Test compatibility function directly
    print("\n=== TYPE COMPATIBILITY TEST ===");
    follow_cls = "__main__.Follow";
    closefriend_cls = "__main__.CloseFriend";
    
    print(f"Is CloseFriend compatible with Follow? {is_arch_cls_compatible(closefriend_cls, follow_cls)}");
    print(f"Is Follow compatible with Follow? {is_arch_cls_compatible(follow_cls, follow_cls)}");
    
    # Test traversal
    print("\n=== TRAVERSAL TEST ===");
    follow_result = [root->:Follow:->];
    print(f"Follow filter found {len(follow_result)} nodes:");
    i = 0;
    for node in follow_result {
        print(f"  {i}: {node.name}");
        i += 1;
    }
    
    # Test with explicit CloseFriend filter
    print("\n=== CLOSEFRIEND TRAVERSAL TEST ===");
    closefriend_result = [root->:CloseFriend:->];
    print(f"CloseFriend filter found {len(closefriend_result)} nodes:");
    i = 0;
    for node in closefriend_result {
        print(f"  {i}: {node.name}");
        i += 1;
    }
}
