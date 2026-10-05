"""Parser, checked Python generation and actual CPU walker execution tests."""
import contextlib
import io
from pathlib import Path
import random
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'jac/tests/runtimelib/fixtures/cursors'


class NamedCursorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from jaclang.runtime.runtime import JacRuntime
        from jaclang.runtime.context import ExecutionContext
        from jaclang.compiler.driver.program import JacProgram
        from jaclang.compiler.driver.compile_options import CompileOptions
        cls.jac, cls.program, cls.options = JacRuntime, JacProgram, CompileOptions
        base, target = JacRuntime.get_base_path_dir(), JacRuntime.get_full_target_path()
        try:
            JacRuntime.set_base_path(None)
            JacRuntime.set_full_target_path(None)
            cls.context = ExecutionContext()
        finally:
            JacRuntime.set_base_path(base)
            JacRuntime.set_full_target_path(target)
        cls.token = JacRuntime.push_request_context(cls.context)
        cls.module = JacRuntime.jac_import(target='program', base_path=str(FIXTURES))[0]
        cls.tmp = tempfile.TemporaryDirectory(prefix='jac-cursors-')

    @classmethod
    def tearDownClass(cls):
        try:
            cls.context.close()
        finally:
            cls.jac.reset_request_context(cls.token)
            cls.tmp.cleanup()

    def chain(self, values, edge):
        nodes = [self.module.Scalar(value=v) for v in values]
        for a, b in zip(nodes, nodes[1:]):
            self.jac.connect(a, b, edge)
        return nodes

    def run_dot(self, left, right, reverse=False):
        visitor = self.module.Dot()
        bindings = {'a': left, 'b': right}
        result = self.jac.spawn(visitor, bindings) if reverse else self.jac.spawn(bindings, visitor)
        self.assertIs(result, visitor)
        return visitor

    def test_same_type_dot_and_different_lengths(self):
        for a, b in [([1, 2, 3], [4, 5, 6]), ([2], [3, 4]), ([2, 7], [3]), ([], [2]), ([2], [])]:
            left, right = self.chain(a, self.module.RowNext), self.chain(b, self.module.ColumnNext)
            w = self.run_dot(left[0] if left else None, right[0] if right else None)
            self.assertEqual(w.total, sum(x * y for x, y in zip(a, b)))
            self.assertEqual(w.pairs, list(zip(a, b)))

    def test_queue_starts_and_duplicates(self):
        a, b = self.module.Scalar(value=2), self.module.Scalar(value=3)
        w = self.run_dot([a, a], [b, b], reverse=True)
        self.assertEqual(w.total, 12)
        self.assertEqual(w.pairs, [(2, 3), (2, 3)])
        self.assertEqual(self.run_dot([], []).pairs, [])

    def test_heterogeneous_channels_change_types(self):
        a = self.module.Bridge(); b = self.module.Other(weight=1)
        x, y = self.module.Scalar(value=6), self.module.Scalar(value=7)
        self.jac.connect(a, x, self.module.RowNext)
        self.jac.connect(b, y, self.module.ColumnNext)
        w = self.jac.spawn({'a': a, 'b': b}, self.module.Heterogeneous())
        self.assertEqual((w.total, w.events), (42, ['bridge', 'product']))

    def test_type_mismatch_is_not_search_or_repeated_condition(self):
        a, b = self.module.Bridge(), self.module.Scalar(value=7)
        self.jac.connect(a, self.module.Scalar(value=6), self.module.RowNext)
        w = self.run_dot([a, self.module.Scalar(value=6)], [b, b])
        self.assertEqual(w.pairs, [(6, 7)])
        w = self.run_dot(a, b)
        self.assertEqual(w.pairs, [])

    def test_no_visit_exhausts_only_after_pending_siblings(self):
        left = self.chain([1, 2, 3], self.module.RowNext)
        right = self.chain([4, 5, 6], self.module.ColumnNext)
        w = self.jac.spawn({'a': left[0], 'b': right[0]}, self.module.StopOne())
        self.assertEqual(w.count, 1)
        w = self.jac.spawn({'a': left[0], 'b': right[:2]}, self.module.StopOne())
        self.assertEqual(w.count, 2)

    def test_branch_successors_are_fifo_zip_not_cartesian(self):
        a = self.chain([1, 2], self.module.RowNext)
        a3 = self.module.Scalar(value=3)
        self.jac.connect(a[0], a3, self.module.RowNext)
        b = self.chain([10, 20], self.module.ColumnNext)
        b3 = self.module.Scalar(value=30)
        self.jac.connect(b[0], b3, self.module.ColumnNext)
        w = self.run_dot(a[0], b[0])
        self.assertEqual(w.pairs, [(1, 10), (2, 20), (3, 30)])

    def test_joint_abilities_declaration_order_and_stable_nodes(self):
        a = self.chain([1, 10], self.module.RowNext)
        b = self.chain([2, 20], self.module.ColumnNext)
        w = self.jac.spawn({'a': a[0], 'b': b[0]}, self.module.Ordered())
        self.assertEqual(w.events, ['first', 'second', 'first', 'second'])

    def test_invalid_bindings_and_node_callbacks_are_rejected(self):
        a = self.module.Scalar(value=1)
        for binding in ({'a': a}, {'a': a, 'b': a, 'c': a}, {'a': a, 'b': 7}, {'a': [a, 7], 'b': a}):
            visitor = self.module.Dot()
            with self.assertRaises(TypeError):
                self.jac.spawn(binding, visitor)
            self.assertEqual(visitor.total, 0)
        with self.assertRaises(TypeError):
            self.jac.spawn(a, self.module.Dot())
        with self.assertRaises(TypeError):
            self.jac.spawn({'a': a, 'b': a}, self.module.Legacy())
        with self.assertRaisesRegex(TypeError, 'Node event'):
            self.jac.spawn({'a': self.module.Active(), 'b': a}, self.module.Dot())
        self.assertEqual(self.run_dot(self.module.Active(), None).total, 0)
        inherited = type('InheritedDot', (self.module.Dot,), {})
        with self.assertRaisesRegex(TypeError, 'inheritance'):
            self.jac.spawn({'a': a, 'b': a}, inherited())
        destroyed = self.module.Scalar(value=5)
        self.jac.destroy(destroyed)
        with self.assertRaisesRegex(RuntimeError, 'destroyed'):
            self.run_dot(destroyed, a)
        with self.assertRaisesRegex(TypeError, 'node targets'):
            self.jac.spawn({'a': a, 'b': a}, self.module.EdgeTarget())

    def test_legacy_entry_exit_visit_order(self):
        nodes = self.chain([1, 2], self.module.RowNext)
        w = self.jac.spawn(nodes[0], self.module.Legacy())
        self.assertEqual(w.events, ['start', 'entry1', 'entry2', 'exit2', 'exit1', 'finish'])

    def test_random_shared_scalar_matmul(self):
        with contextlib.redirect_stdout(io.StringIO()):
            m = self.jac.jac_import(target='matmul', base_path=str(ROOT / 'jac/examples/cursors'))[0]
        rng = random.Random(173)
        for rows, inner, cols in [(1, 1, 1), (2, 3, 2), (3, 2, 4)]:
            a = [[rng.randrange(-5, 6) for _ in range(inner)] for _ in range(rows)]
            b = [[rng.randrange(-5, 6) for _ in range(cols)] for _ in range(inner)]
            actual = m.multiply(a, b)
            self.assertEqual([[n.value for n in row] for row in actual],
                             [[sum(a[i][k] * b[k][j] for k in range(inner)) for j in range(cols)] for i in range(rows)])
            for row in actual:
                for node in row:
                    self.assertEqual([key for key in vars(node) if not key.startswith('_')], ['value'])

    def test_front_insertion_visit_else_reports_and_disengage(self):
        a = self.chain([1, 2], self.module.RowNext)
        b = self.chain([10, 20, 30], self.module.ColumnNext)
        with contextlib.redirect_stdout(io.StringIO()):
            w = self.jac.spawn({'a': [a[0], self.module.Scalar(value=3)], 'b': b[0]}, self.module.InsertAndReport())
        self.assertEqual(w.events, [(1, 10), (2, 20), (3, 30)])
        self.assertEqual(w.reports, [1, 2, 3, -1])
        stopped = self.jac.spawn({'a': a[0], 'b': b[0]}, self.module.FinishEarly())
        self.assertEqual(stopped.count, 1)

    def test_node_subtypes_and_runtime_failure_cleanup(self):
        from jaclang.runtime.osp_kernel import scope_of
        w = self.run_dot(self.module.SubScalar(value=8), self.module.Scalar(value=9))
        self.assertEqual(w.total, 72)
        bad = self.module.Dot()
        with self.assertRaises(TypeError):
            self.jac.spawn({'a': self.module.Active(), 'b': self.module.Scalar(value=1)}, bad)
        self.assertIsNone(scope_of(bad))
        self.jac.spawn({'a': self.module.Scalar(value=2), 'b': self.module.Scalar(value=3)}, bad)
        self.assertEqual(bad.total, 6)

    def test_three_channels_nested_spawn_and_explicit_origins(self):
        nodes = [self.module.Scalar(value=v) for v in (2, 3, 4)]
        three = self.jac.spawn(dict(zip(('a', 'b', 'c'), nodes)), self.module.Three())
        self.assertEqual(three.total, 9)
        early_return = self.jac.spawn({'a': nodes[0], 'b': nodes[1]}, self.module.ReturnAbility())
        self.assertEqual(early_return.count, 2)
        with contextlib.redirect_stdout(io.StringIO()):
            parent = self.jac.spawn({'a': nodes[0], 'b': nodes[1]}, self.module.Nested())
        self.assertEqual(parent.total, 6)
        self.assertEqual(parent.reports, [2, 3])
        self.jac.connect(nodes[0], nodes[2], self.module.RowNext)
        self.jac.connect(nodes[0], nodes[1], self.module.ColumnNext)
        w = self.jac.spawn({'a': nodes[0], 'b': nodes[2]}, self.module.ExplicitOrigins())
        self.assertEqual(w.pairs, [(2, 4), (4, 3)])

    def compile_source(self, source):
        path = Path(self.tmp.name) / 'check.jac'
        path.write_text(source)
        program = self.program()
        program.compile(file_path=str(path), options=self.options(no_cgen=True, need_full_ast=True, no_ir_cache=True))
        return program

    def test_checked_spawn_bindings_and_cursor_field_types(self):
        source = '''node N { has value: int = 1; }
walker W { cursor a, b; has total: int = 0;
can step with (a: N entry, b: N entry) { self.total += here[a].value; }}
with entry {
    w = {"a": N(), "b": N()} spawn W();
    empty = W() spawn {"a": None, "b": [N(), N()]};
    assert w.total == 1 and empty.total == 0;
}'''
        p = self.compile_source(source)
        self.assertFalse(p.errors_had, str(p.errors_had))
        p = self.compile_source(source.replace('here[a].value;', 'here[a].missing;'))
        self.assertTrue(p.errors_had)

    def test_semantic_rejections(self):
        prefix = 'node N { has value: int = 1; } edge E {}\n'
        for body in (
            'cursor a, a; can f with (a: N entry, a: N entry) {}',
            'cursor a, b; can f with (a: N entry) {}',
            'cursor a, b; can f with (a: N exit, b: N entry) {}',
            'cursor a, b; can f with N entry {}',
            'cursor a, b; can f with (a: N entry, b: N entry) { visit[x] [->:E:->]; }',
            'cursor a, b; can f with (a: N entry, b: N entry) { x = here; }',
            'cursor a, b; can f with (a: N entry, b: N entry) { x = here[x]; }',
            'cursor a, b; can f with (a: N entry, b: N entry) { visit [->:E:->]; }',
            'cursor a, b; can f with (a: N entry, b: N entry) { here[a] = here[b]; }',
            'can f with (a: N entry, b: N entry) {}',
            'cursor a, b; def helper() { visit[a] [->:E:->]; }',
            'cursor a, b; can f with (a: int entry, b: N entry) {}',
            'cursor a, b; async can f with (a: N entry, b: N entry) {}',
            'cursor a; cursor b; can f with (a: N entry, b: N entry) {}',
        ):
            with self.subTest(body=body):
                p = self.compile_source(prefix + 'walker W { ' + body + ' }')
                self.assertTrue(p.errors_had)


if __name__ == '__main__':
    unittest.main()
