"""Host packing, CUDA ABI and lifecycle checks without a GPU."""

import io;
import runpy;
import sys;
import unittest;
import from pathlib { Path }
import from tests.support { TESTS_DIR }

test "GPU runtime accepts actual walkers and safely manages packed batches" {
    repo = Path(TESTS_DIR).resolve().parents[1];
    scripts = repo / "scripts/gpu_walker";
    old_path = sys.path.copy();
    try {
        sys.path.insert(0, str(scripts));
        module = runpy.run_path(str(scripts / "test_runtime.py"));
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(
            module["RuntimeTests"]
        );
        log = io.StringIO();
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite);
        assert result.wasSuccessful() , log.getvalue();
        assert result.testsRun == 10;
    } finally {
        sys.path[:] = old_path;
    }
}

test "GPU example accepts typed Jac walker and node lists" {
    import from jaclang.compiler.driver.program { JacProgram }
    import from jaclang.compiler.driver.compile_options { CompileOptions }
    repo = Path(TESTS_DIR).resolve().parents[1];
    program = JacProgram();
    program.compile(
        file_path=str(repo / "jac/examples/gpu/chain_run.jac"),
        options=CompileOptions(no_cgen=True, force_target_program=True)
    );
    assert not program.errors_had , "\n".join(
        error.pretty_print() for error in program.errors_had
    );
}

test "GPU integer walkers match serial arithmetic and preserve failed batches" {
    repo = Path(TESTS_DIR).resolve().parents[1];
    scripts = repo / "scripts/gpu_walker";
    old_path = sys.path.copy();
    try {
        sys.path.insert(0, str(scripts));
        module = runpy.run_path(str(scripts / "test_integers.py"));
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(
            module["IntegerWalkerTests"]
        );
        log = io.StringIO();
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite);
        assert result.wasSuccessful() , log.getvalue();
        assert result.testsRun == 6;
    } finally {
        sys.path[:] = old_path;
    }
}

test "CSR walkers preserve FIFO visits and safely manage bounded queues" {
    repo = Path(TESTS_DIR).resolve().parents[1];
    scripts = repo / "scripts/gpu_walker";
    old_path = sys.path.copy();
    try {
        sys.path.insert(0, str(scripts));
        module = runpy.run_path(str(scripts / "test_csr.py"));
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(
            module["CsrWalkerTests"]
        );
        log = io.StringIO();
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite);
        assert result.wasSuccessful() , log.getvalue();
        assert result.testsRun == 8;
    } finally {
        sys.path[:] = old_path;
    }
}

test "CSR example accepts typed Jac graph and walker lists" {
    import from jaclang.compiler.driver.program { JacProgram }
    import from jaclang.compiler.driver.compile_options { CompileOptions }
    repo = Path(TESTS_DIR).resolve().parents[1];
    program = JacProgram();
    program.compile(
        file_path=str(repo / "jac/examples/gpu/csr_graph_run.jac"),
        options=CompileOptions(no_cgen=True, force_target_program=True)
    );
    assert not program.errors_had , "\n".join(
        error.pretty_print() for error in program.errors_had
    );
}

test "GPU node fields use aligned SoA columns and enforce nested ownership" {
    repo = Path(TESTS_DIR).resolve().parents[1];
    scripts = repo / "scripts/gpu_walker";
    old_path = sys.path.copy();
    try {
        sys.path.insert(0, str(scripts));
        module = runpy.run_path(str(scripts / "test_fields.py"));
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(
            module["NodeFieldTests"]
        );
        log = io.StringIO();
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite);
        assert result.wasSuccessful() , log.getvalue();
        assert result.testsRun == 8;
    } finally {
        sys.path[:] = old_path;
    }
}

test "Multi-field GPU example accepts nested Jac data objects" {
    import from jaclang.compiler.driver.program { JacProgram }
    import from jaclang.compiler.driver.compile_options { CompileOptions }
    repo = Path(TESTS_DIR).resolve().parents[1];
    program = JacProgram();
    program.compile(
        file_path=str(repo / "jac/examples/gpu/multi_field_run.jac"),
        options=CompileOptions(no_cgen=True, force_target_program=True)
    );
    assert not program.errors_had , "\n".join(
        error.pretty_print() for error in program.errors_had
    );
}
