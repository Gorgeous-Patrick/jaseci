"""Tests for AST serialization and deserialization.

Verifies that the Jac AST can be serialized to disk via pickle and
correctly deserialized at runtime, preserving tree structure, token
data, and node types.
"""

import os;
import pickle;
import from pathlib { Path }
import jaclang;
import from jaclang.jac0core.program { JacProgram }
import from jaclang.jac0core.unitree {
    UniNode,
    Module,
    Token,
    Name,
    UniScopeNode,
    NameAtom,
    Expr,
    Symbol
}
import from jaclang.jac0core.bccache { DiskBytecodeCache, CacheKey }
import from jaclang.jac0core.compiler { _recalculate_parents }

glob JAC_ROOT = str(Path(jaclang.__file__).parent.parent),
     EXAMPLES = os.path.join(JAC_ROOT, "examples");

test "basic ast pickle roundtrip" {
    """Test that a compiled AST can be pickled and unpickled."""
    prog = JacProgram();
    prog.compile(os.path.join(EXAMPLES, "micro", "hodge_podge.jac"));
    assert len(prog.errors_had) == 0;
    # Get the main module from hub
    main_mod: (Module | None) = None;
    for (path, mod) in prog.mod.hub.items() {
        if path.endswith("hodge_podge.jac") {
            main_mod = mod;
            break;
        }
    }
    assert main_mod is not None , "hodge_podge module not found in hub";
    # Serialize and deserialize
    data = pickle.dumps(main_mod, protocol=pickle.HIGHEST_PROTOCOL);
    assert len(data) > 0;
    restored: Module = pickle.loads(data);
    # Rebuild parent pointers
    _recalculate_parents(restored);
    # Verify it's a Module
    assert isinstance(restored, Module);
    assert restored.name == main_mod.name;
}

test "tree structure preserved after roundtrip" {
    """Test that the tree structure (kid counts, node types) is preserved."""
    prog = JacProgram();
    code = 'with entry { x = 1 + 2; print(x); }';
    result = prog.compile(use_str=code, file_path="test_tree.jac");
    assert result is not None;
    # result is the Module directly from compile()
    main_mod = result;
    original_kid_count = len(main_mod.kid);
    original_flat = main_mod.flatten();
    original_types = [`type(n).__name__ for n in original_flat];
    # Roundtrip
    data = pickle.dumps(main_mod, protocol=pickle.HIGHEST_PROTOCOL);
    restored: Module = pickle.loads(data);
    _recalculate_parents(restored);
    restored_flat = restored.flatten();
    restored_types = [`type(n).__name__ for n in restored_flat];
    assert len(restored.kid) == original_kid_count;
    assert len(restored_flat) == len(original_flat);
    assert restored_types == original_types;
}

test "token data preserved after roundtrip" {
    """Test that Token values, line numbers, etc. are preserved."""
    prog = JacProgram();
    code = 'glob message = "hello world";';
    result = prog.compile(use_str=code, file_path="test_token.jac");
    assert result is not None;
    main_mod = result;
    # Collect original tokens
    original_tokens = [
        n
        for n in main_mod.flatten()
        if isinstance(n, Token)
    ];
    # Roundtrip
    data = pickle.dumps(main_mod, protocol=pickle.HIGHEST_PROTOCOL);
    restored: Module = pickle.loads(data);
    _recalculate_parents(restored);
    restored_tokens = [
        n
        for n in restored.flatten()
        if isinstance(n, Token)
    ];
    assert len(restored_tokens) == len(original_tokens);
    for (orig, rest) in zip(original_tokens, restored_tokens) {
        assert orig.value == rest.value;
        assert orig.name == rest.name;
        assert orig.line_no == rest.line_no;
    }
}

test "parent pointers rebuilt correctly" {
    """Test that _recalculate_parents correctly rebuilds parent pointers."""
    prog = JacProgram();
    code = 'can foo(x: int) -> int { return x + 1; }';
    result = prog.compile(use_str=code, file_path="test_parents.jac");
    assert result is not None;
    # Use the compiled result directly instead of looking up in hub
    data = pickle.dumps(result, protocol=pickle.HIGHEST_PROTOCOL);
    restored: Module = pickle.loads(data);
    # Before _recalculate_parents, parent should be None (excluded from state)
    for kid in restored.kid {
        assert kid.parent is None;
    }
    # Rebuild parents
    _recalculate_parents(restored);
    # After rebuild, parent should point back correctly
    for kid in restored.kid {
        assert kid.parent is restored;
    }
}

test "disk cache ast roundtrip" {
    """Test AST save/load through DiskBytecodeCache."""
    import tempfile;
    # Create a real temp .jac file so _is_valid can check mtime
    tmp_dir = tempfile.mkdtemp();
    tmp_file = os.path.join(tmp_dir, "test_cache.jac");
    with open(tmp_file, 'w') as f {
        f.write('with entry { print("cache test"); }');
    }
    prog = JacProgram();
    result = prog.compile(file_path=tmp_file);
    assert result is not None;
    assert len(prog.errors_had) == 0;
    main_mod: (Module | None) = None;
    for (path, mod) in prog.mod.hub.items() {
        if "test_cache" in path {
            main_mod = mod;
            break;
        }
    }
    assert main_mod is not None;
    # Create a cache and test put/get
    cache = DiskBytecodeCache();
    cache_key = CacheKey.for_source(tmp_file);
    # First store the bytecode so _is_valid has a reference for mtime comparison
    cache.put(cache_key, main_mod.gen.py_bytecode);
    # Now store and retrieve AST
    cache.put_ast(cache_key, main_mod);
    loaded_raw = cache.get_ast(cache_key);
    assert loaded_raw is not None;
    assert isinstance(loaded_raw, Module);
    if loaded_raw is not None {
        _recalculate_parents(loaded_raw);
        # Verify tree matches
        original_flat = main_mod.flatten();
        loaded_flat = loaded_raw.flatten();
        assert len(loaded_flat) == len(original_flat);
    }
    # Cleanup
    import shutil;
    shutil.rmtree(tmp_dir, ignore_errors=True);
}

test "default fields restored after deserialization" {
    """Test that excluded fields get proper defaults and symtab fields are preserved."""
    prog = JacProgram();
    code = 'can bar() { pass; }';
    result = prog.compile(use_str=code, file_path="test_defaults.jac");
    assert result is not None;
    main_mod = result;
    data = pickle.dumps(main_mod, protocol=pickle.HIGHEST_PROTOCOL);
    restored: Module = pickle.loads(data);
    # Check UniNode defaults for transient fields
    assert restored._gen is None;
    assert restored._in_mod_nodes == [];
    # Check UniScopeNode — symtab fields are now PRESERVED (not reset)
    assert isinstance(restored, UniScopeNode);
    # Module has no parent_scope (top-level)
    assert restored.parent_scope is None;
    # Symbol table should be preserved — 'bar' was defined in this module
    assert len(restored.names_in_scope) > 0, "names_in_scope should be preserved";
    assert 'bar' in restored.names_in_scope, "'bar' should be in names_in_scope";
    # kid_scope should have at least the Ability scope for 'bar'
    assert len(restored.kid_scope) > 0, "kid_scope should be preserved";
}

test "symbol table preserved after roundtrip" {
    """Test that symbol tables and symbol references survive serialization."""
    prog = JacProgram();
    code = 'glob greeting = "hello";\ncan add(x: int, y: int) -> int { return x + y; }';
    result = prog.compile(use_str=code, file_path="test_symtab.jac");
    assert result is not None;
    main_mod = result;
    # Verify original has symbols before roundtrip
    assert len(main_mod.names_in_scope) > 0, "pre-roundtrip: names_in_scope empty";
    # Roundtrip
    data = pickle.dumps(main_mod, protocol=pickle.HIGHEST_PROTOCOL);
    restored: Module = pickle.loads(data);
    _recalculate_parents(restored);
    # 1. names_in_scope preserved
    assert len(restored.names_in_scope) > 0, "names_in_scope should be non-empty";
    assert 'greeting' in restored.names_in_scope, "'greeting' should be in scope";
    assert 'add' in restored.names_in_scope, "'add' should be in scope";
    # 2. lookup returns a Symbol
    sym = restored.lookup('add', deep=False);
    assert sym is not None, "lookup('add') should return a Symbol";
    assert isinstance(sym, Symbol);
    assert sym.sym_name == 'add';
    # 3. Symbol.defn points to a NameAtom with correct _sym back-reference
    assert len(sym.defn) > 0, "Symbol should have at least one defn";
    defn_node = sym.defn[0];
    assert isinstance(defn_node, NameAtom);
    assert defn_node._sym is sym, "NameAtom._sym should point back to the Symbol";
    # 4. Symbol.parent_tab points back to the module scope
    assert sym.parent_tab is restored, "Symbol.parent_tab should reference the module";
    # 5. kid_scope chain — 'add' ability should have its own scope
    assert len(restored.kid_scope) > 0, "Module should have kid scopes";
    ability_scope = None;
    for ks in restored.kid_scope {
        if hasattr(ks, 'scope_name') and 'add' in str(ks.scope_name) {
            ability_scope = ks;
            break;
        }
    }
    if ability_scope is not None {
        assert ability_scope.parent_scope is restored, "Ability scope parent should be module";
        # Parameters should be in the ability's scope
        assert len(ability_scope.names_in_scope) > 0, "Ability scope should have params";
    }
}

test "get_ast loads on demand from disk cache" {
    """Test that JacProgram.get_ast() lazily loads AST from disk cache."""
    import tempfile;
    tmp_dir = tempfile.mkdtemp();
    tmp_file = os.path.join(tmp_dir, "test_lazy.jac");
    with open(tmp_file, 'w') as f {
        f.write('with entry { print("lazy load"); }');
    }
    resolved = os.path.realpath(tmp_file);
    # Use get_bytecode to trigger compilation + disk cache write (put_ast).
    prog = JacProgram();
    bc = prog.get_bytecode(resolved);
    assert bc is not None;
    # The module should now be in the hub from compilation.
    assert resolved in prog.mod.hub;
    # Remove from hub to simulate a fresh process.
    del prog.mod.hub[resolved];
    assert resolved not in prog.mod.hub;
    # get_ast should load it from disk cache on demand.
    loaded = prog.get_ast(resolved);
    assert loaded is not None;
    assert isinstance(loaded, Module);
    # Now it should be back in the hub.
    assert resolved in prog.mod.hub;
    # Cleanup
    import shutil;
    shutil.rmtree(tmp_dir, ignore_errors=True);
}
