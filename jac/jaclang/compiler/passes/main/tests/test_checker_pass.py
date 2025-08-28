
"""Tests for typechecker pass (the pyright implementation)."""

from tempfile import NamedTemporaryFile

from jaclang.utils.test import TestCase
from jaclang.compiler.passes.main import TypeCheckPass
from jaclang.compiler.program import JacProgram


class TypeCheckerPassTests(TestCase):
    """Test class obviously."""

    def test_explicit_type_annotation_in_assignment(self) -> None:
        """Test explicit type annotation in assignment."""
        program = JacProgram()
        program.build(
            self.fixture_abs_path("type_annotation_assignment.jac"), type_check=True
        )
        self.assertEqual(len(program.errors_had), 2)
        self._assert_error_pretty_found("""
            glob should_fail1: int = "foo";
                 ^^^^^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())

        self._assert_error_pretty_found("""
            glob should_fail2: str = 42;
                 ^^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[1].pretty_print())

    def test_infer_type_of_assignment(self) -> None:
        program = JacProgram()
        mod = program.compile(self.fixture_abs_path("infer_type_assignment.jac"))
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)

        self._assert_error_pretty_found("""
          assigning_to_str: str = some_int_inferred;
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())

    def test_member_access_type_resolve(self) -> None:
        program = JacProgram()
        mod = program.compile(self.fixture_abs_path("member_access_type_resolve.jac"))
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)
        self._assert_error_pretty_found("""
          s: str = f.bar.baz;
          ^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())

    def test_member_access_type_infered(self) -> None:
        program = JacProgram()
        mod = program.compile(self.fixture_abs_path("member_access_type_inferred.jac"))
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)
        self._assert_error_pretty_found("""
          s = f.bar;
          ^^^^^^^^^
        """, program.errors_had[0].pretty_print())

    def test_import_symbol_type_infer(self) -> None:
        src = """
        import math as alias;
        with entry {

          # math module imports sys so it has the symbol
          # we're not using math.pi since it's a Final[float]
          # and we haven't implemented generic types yet.
          m = alias;

          i: int = m.sys.prefix; # <-- Error
          s: str = m.sys.prefix; # <-- Ok
        }
        """
        program = JacProgram()
        mod = program.compile("main.jac", use_str=src)
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)
        self._assert_error_pretty_found("""
            i: int = m.sys.prefix;
            ^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())


    def _assert_error_pretty_found(self, needle: str, haystack: str) -> None:
        for line in [line.strip() for line in needle.splitlines() if line.strip()]:
            self.assertIn(line, haystack, f"Expected line '{line}' not found in:\n{haystack}")
