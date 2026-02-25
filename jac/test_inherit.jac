import from jaclang.jac0core.runtime { resolve_arch_type, is_arch_cls_compatible }

with entry {
    # Test the functions
    edge_cls = "test_inherit.CloseFriend";
    base_cls = "test_inherit.Follow";
    
    print("Testing type resolution...");
    print(f"edge_cls: {edge_cls}");
    print(f"base_cls: {base_cls}");
    
    # This should work correctly
    try {
        result = is_arch_cls_compatible(edge_cls, base_cls);
        print(f"Is CloseFriend compatible with Follow? {result}");
    } except Exception as e {
        print(f"Error: {e}");
    }
}

edge Follow {}
edge CloseFriend(Follow) {}
