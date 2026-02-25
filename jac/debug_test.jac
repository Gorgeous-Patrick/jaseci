edge Follow {}
edge CloseFriend(Follow) {}
node Person { has name: str; }

with entry {
    p1 = Person(name="Alice");
    root +>: Follow :+> p1;
    root +>: CloseFriend :+> p1;
    
    root_anch = root.__jac__;
    
    # Debug print arch_cls values
    for edge in root_anch.edges {
        cls = type(edge.archetype);
        arch_cls_str = f"{cls.__module__}.{cls.__qualname__}";
        print(f"Edge type: {cls.__name__}, arch_cls: {arch_cls_str}");
        
        # Test stub
        stub = edge.make_stub();
        print(f"Stub arch_cls: {stub.__dict__.get('arch_cls')}");
    }
}
