
"""Tests for typechecker pass (the pyright implementation)."""

from tempfile import NamedTemporaryFile

from jaclang.utils.test import TestCase
from jaclang.compiler.passes.main import TypeCheckPass
from jaclang.compiler.program import JacProgram


class TypeCheckerPassTests(TestCase):
    """Test class obviously."""

    def test_explicit_type_annotation_in_assignment(self) -> None:
        """Test explicit type annotation in assignment."""
        src = """
        glob should_pass1: int = 42;
        glob should_fail1: int = "foo";
        glob should_pass2: str = "bar";
        glob should_fail2: str = 42;

        # This is without any explicit type annotation.
        # was failing after the first PR.
        glob should_be_fine = "baz";
        """
        program = JacProgram()
        program.build("main.jac", use_str=src, type_check=True)
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
        src = """
        with entry {
          some_int_inferred = 42;
          assigning_to_int: int = some_int_inferred; # <-- Ok
          assigning_to_str: str = some_int_inferred; # <-- Error
        }
        """
        program = JacProgram()
        mod = program.compile("main.jac", use_str=src)
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)

        self._assert_error_pretty_found("""
          assigning_to_str: str = some_int_inferred;
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())

    def test_member_access_type_resolve(self) -> None:
        src = """
        node Bar {
          has baz: int;
        }
        node Foo {
          has bar: Bar;
        }
        with entry {
          f: Foo = Foo();
          i: int = f.bar.baz; # <-- Ok
          s: str = f.bar.baz; # <-- Error
        }
        """
        program = JacProgram()
        mod = program.compile("main.jac", use_str=src)
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)
        self._assert_error_pretty_found("""
          s: str = f.bar.baz;
          ^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())

    def test_member_access_type_infered(self) -> None:
        src = """
        node Foo {
          # We can infer the type of `bar` but the jac
          # syntax makes the type annotation a must here.
          has bar: int = 42;
        }
        with entry {
          f: Foo = Foo();

          i = 42; s = "foo";

          i = f.bar; # <-- Ok
          s = f.bar; # <-- Error
        }
        """
        program = JacProgram()
        mod = program.compile("main.jac", use_str=src)
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 1)
        self._assert_error_pretty_found("""
          s = f.bar;
          ^^^^^^^^^
        """, program.errors_had[0].pretty_print())

    def _assert_error_pretty_found(self, needle: str, haystack: str) -> None:
        for line in [line.strip() for line in needle.splitlines() if line.strip()]:
            self.assertIn(line, haystack, f"Expected line '{line}' not found in:\n{haystack}")
