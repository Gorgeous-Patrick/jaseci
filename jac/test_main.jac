import from jaclang.jac0core.runtime { resolve_arch_type, is_arch_cls_compatible }

edge Follow {}
edge CloseFriend(Follow) {}

with entry {
    edge_cls = "__main__.CloseFriend";
    base_cls = "__main__.Follow";
    
    print("Testing type resolution...");
    print(f"edge_cls: {edge_cls}");
    print(f"base_cls: {base_cls}");
    
    # Check if types exist
    print(f"Follow type: {Follow}");
    print(f"CloseFriend type: {CloseFriend}");
    print(f"CloseFriend MRO: {CloseFriend.__mro__}");
    
    try {
        result = is_arch_cls_compatible(edge_cls, base_cls);
        print(f"Is CloseFriend compatible with Follow? {result}");
    } except Exception as e {
        print(f"Error: {e}");
        import traceback;
        traceback.print_exc();
    }
}
