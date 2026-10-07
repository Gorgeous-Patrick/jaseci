"""Named-cursor GPU compilation and CPU differential of device control flow."""
import runpy;
import unittest;
import io;
import sys;
import from pathlib { Path }
import from tests.support { TESTS_DIR }

test "named GPU cursors and batch BFS preserve CPU arrival semantics" {
    folder = Path(TESTS_DIR).resolve().parents[1] / "scripts/gpu_walker";
    sys.path.insert(0, str(folder));
    try {
        suite = runpy.run_path(str(folder / "test_named_cursors.py"));
        loaded = unittest.defaultTestLoader.loadTestsFromTestCase(suite["NamedGpuTests"]);
        log = io.StringIO();
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(loaded);
        assert result.testsRun >= 12;
        assert result.wasSuccessful() , log.getvalue();
    } finally {
        sys.path.remove(str(folder));
    }
}
