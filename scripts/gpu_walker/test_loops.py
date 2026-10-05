"""Real backedge lowering: LLVM host JIT; opt-in CUDA via inherited runner."""
from pathlib import Path
import test_integers
from verify import CpuKernel


class LoopTests(test_integers.IntegerWalkerTests):
    def test_dynamic_nested_loops(self):
        spec, module = self.variant('''remaining = here.value;
for i in range(here.value) {
    for j in range(i) { self.total += i + j; }
}
while remaining > 0 { self.total += remaining; remaining -= 1; }''')
        cpu = CpuKernel(spec)
        self.assertIn('loop.check', cpu.ir)
        values, links, heads, seeds = [3, 2, 0, -4], [1, -1, -1, -1], [0, 1, 2, 3, -1], [0]*5
        self.assertEqual(self.runner(spec)(values, links, heads, seeds),
                         (self.reference(module, values, links, heads, seeds), [0]*5))

    def test_negative_step_and_single_evaluation(self):
        spec, module = self.variant('''bound = here.value;
for i in range(bound, -2, -2) { self.total += i; bound -= 1; }''')
        values = [5, 0, -3]
        self.assertEqual(self.runner(spec)(values, [-1]*3, [0, 1, 2], [0]*3),
                         (self.reference(module, values, [-1]*3, [0, 1, 2], [0]*3), [0]*3))

    def test_loop_condition_and_branch_carried_state(self):
        spec, module = self.variant('''i = 0;
while i < here.value {
    if i % 2 == 0 { self.total += i; } else { self.total -= i; }
    i += 1;
}''')
        self.assertEqual(self.runner(spec)([8], [-1], [0], [9]),
                         (self.reference(module, [8], [-1], [0], [9]), [0]))

    def test_range_int64_endpoints(self):
        for body, expected in (
            ('for i in range(9223372036854775806, 9223372036854775807, 2) { self.total += 1; }', 1),
            ('for i in range(-9223372036854775807, -9223372036854775808, -2) { self.total += 1; }', 1)):
            spec, _ = self.variant(body)
            self.assertEqual(self.runner(spec)([0], [-1], [0], [0]), ([expected], [0]))

    def test_loop_arithmetic_failure_status(self):
        spec, _ = self.variant('for i in range(3) { self.total += here.value; }')
        result, status = self.runner(spec)([2**62, 1], [-1, -1], [0, 1], [0, 0])
        self.assertEqual(status, [3, 0])
        self.assertEqual(result[1], 3)
        spec, _ = self.variant('i = 2; while i >= 0 { self.total += here.value % i; i -= 1; }')
        self.assertEqual(self.runner(spec)([7], [-1], [0], [0])[1], [4])

    def test_shadowed_range_is_rejected(self):
        path = Path(self.tmp.name) / 'shadowed_range.jac'
        path.write_text('''def range(n: int) -> list[int] { return [9]; }
node IntCell { has value: int; } edge IntNext {}
walker EvenSum { has total: int = 0;
can step with IntCell entry {
for i in range(here.value) { self.total += i; }
visit [->:IntNext:->]; }}''')
        with self.assertRaises(self.unsupported):
            self.select(self.frontend(str(path)), ['EvenSum'])

    def test_rejected_loop_constructs(self):
        for body in ('for i in range(here.value, 2, 0) { self.total += i; }',
                     'for i in range(3) { i += 1; }',
                     'while True { break; }', 'while True { continue; }',
                     'while True { visit [->:IntNext:->]; }',
                     'if True { x = 1; } self.total += x;',
                     'for i in range(0) {} self.total += i;',
                     'for i in [1, 2] { self.total += i; }',
                     'while False {} else { self.total += 1; }',
                     'for i in range(0, here.value, here.value) { self.total += i; }'):
            with self.subTest(body=body), self.assertRaises(self.unsupported):
                self.variant(body)


if __name__ == '__main__':
    import unittest
    unittest.main()
