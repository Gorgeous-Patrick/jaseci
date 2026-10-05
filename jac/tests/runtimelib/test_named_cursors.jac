"""Checked Python compilation and real CPU named-cursor execution."""
import runpy;
import unittest;
import io;
import from pathlib { Path }
import from tests.support { TESTS_DIR }

test "named cursor parser codegen runtime and scalar graph matmul" {
    path = Path(TESTS_DIR).resolve().parents[1] / "scripts/test_named_cursors.py";
    suite = runpy.run_path(str(path));
    loaded = unittest.defaultTestLoader.loadTestsFromTestCase(suite["NamedCursorTests"]);
    log = io.StringIO();
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(loaded);
    assert result.testsRun >= 15;
    assert result.wasSuccessful() , log.getvalue();
}
