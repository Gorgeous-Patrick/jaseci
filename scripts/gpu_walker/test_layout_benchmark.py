"""CPU checks for measurement aggregation and semantic physical permutations."""
from array import array
from dataclasses import dataclass, field
from types import SimpleNamespace
import unittest
from layout_benchmark import permute_cursors, summarize


@dataclass
class Buffers:
    cursor_spec: object = field(default_factory=lambda: SimpleNamespace(cursor_names=['a', 'b']))
    node_columns: list = field(default_factory=lambda: [array('q', [10, 20, 30])])
    tags: array = field(default_factory=lambda: array('q', [1, 2, 1]))
    offsets: array = field(default_factory=lambda: array('q', [0, 3, 3, 4, 4, 4, 5, 5]))
    targets: array = field(default_factory=lambda: array('q', [2, 1, 2, 0, 2]))
    heads: array = field(default_factory=lambda: array('q', [0, 2, 1, -1]))
    seed_counts: array = field(default_factory=lambda: array('q', [1, 1, 1, 0]))
    queue: array = field(default_factory=lambda: array('q', [0, -1, 2, -1, 1, -1, -1, -1]))
    initial: array = field(default_factory=lambda: array('q', [7, 8]))
    results: array = field(default_factory=lambda: array('q', [0, 0]))
    status: array = field(default_factory=lambda: array('I', [0, 0]))
    extra_initial: list = field(default_factory=list)
    extra_results: list = field(default_factory=list)
    reports: object = None
    timings: dict = field(default_factory=dict)
    prediction: dict = field(default_factory=dict)

    def columns(self):
        return self.node_columns


class LayoutTests(unittest.TestCase):
    def test_permutation_preserves_order_duplicates_and_lanes(self):
        old = Buffers()
        new = permute_cursors(old, [2, 0, 1])
        inverse = [1, 2, 0]
        self.assertEqual(list(new.node_columns[0]), [30, 10, 20])
        self.assertEqual(list(new.heads), [1, 0, 2, -1])
        self.assertEqual(list(new.seed_counts), list(old.seed_counts))
        self.assertEqual(list(new.initial), [7, 8])
        for cursor in range(2):
            for node in range(3):
                row = cursor * 4 + node
                new_row = cursor * 4 + inverse[node]
                expected = [inverse[t] for t in old.targets[old.offsets[row]:old.offsets[row+1]]]
                self.assertEqual(list(new.targets[new.offsets[new_row]:new.offsets[new_row+1]]), expected)
        self.assertEqual(list(old.heads), [0, 2, 1, -1])
        with self.assertRaises(ValueError):
            permute_cursors(old, [0, 0, 2])

    def test_zero_and_partial_metrics_have_no_invalid_ratios(self):
        rows = [dict(case='tiny', mode='one_shot', phase='measured', seed=1, pair=0,
                     layout=name, predict_us=value, kernel_event_us=2)
                for name, value in [('Current', 0), ('Predicted', 1), ('Random', 0)]]
        rows[-1]['permutation_us'] = 3
        summary = summarize(rows)[0]
        self.assertNotIn('Random_over_Current_predict_us', summary['paired_ratios'])
        self.assertEqual(summary['distributions']['permutation_us']['Random']['median'], 3)


if __name__ == '__main__':
    unittest.main()
