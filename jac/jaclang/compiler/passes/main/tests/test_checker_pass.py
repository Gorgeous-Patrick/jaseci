
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
        """
        program = JacProgram()
        mod = program.compile("main.jac", use_str=src)
        TypeCheckPass(ir_in=mod, prog=program)
        self.assertEqual(len(program.errors_had), 2)
        self._assert_error_pretty_found("""
            glob should_fail1: int = "foo";
                 ^^^^^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[0].pretty_print())

        self._assert_error_pretty_found("""
            glob should_fail2: str = 42;
                 ^^^^^^^^^^^^^^^^^^^^^^
        """, program.errors_had[1].pretty_print())

    def _assert_error_pretty_found(self, needle: str, haystack: str) -> None:
        for line in [line.strip() for line in needle.splitlines() if line.strip()]:
            self.assertIn(line, haystack, f"Expected line '{line}' not found in:\n{haystack}")
