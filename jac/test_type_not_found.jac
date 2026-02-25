import from jaclang.jac0core.runtime { resolve_arch_type }

with entry {
    try {
        t = resolve_arch_type("__main__.NonExistent");
        print(f"Type found: {t}");
    } except Exception as e {
        print(f"Expected error: {e}");
    }
}
