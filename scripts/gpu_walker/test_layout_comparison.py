"""Host-only checks for layout semantics and GPU trace attribution."""

from pathlib import Path
import sqlite3
import tempfile
import unittest

from compare_layouts import attach_kernel_times, sample_order, summarize
from verify import reorder_nodes


class LayoutComparisonTests(unittest.TestCase):
    def test_permutation_preserves_full_paths_and_shared_suffix(self):
        values, links, heads = [2, 3, 5, 7, 11], [2, 3, 4, 4, -1], [0, 1, -1, 2]
        reordered = reorder_nodes(values, links, heads, [4, 2, 0, 3, 1])

        def paths(values, links, heads):
            result = []
            for head in heads:
                path = []
                while head != -1:
                    path.append(values[head])
                    head = links[head]
                result.append(path)
            return result

        self.assertEqual(paths(*reordered), [[2, 5, 11], [3, 7, 11], [], [5, 11]])
        self.assertNotEqual(reordered[2], heads)

    def test_balanced_order_and_paired_summary_exclude_warmups(self):
        order = list(sample_order(928, 2, 4))
        self.assertEqual([x[2] for x in order[:4]], ['Random', 'Ours', 'Ours', 'Random'])
        records = [dict(length=3, seed=928, phase=phase, pair=pair, layout=label,
                        kernel_us=(9999 if phase == 'warmup' else
                                   (pair + 1) * (2 if label == 'Random' else 1)))
                   for phase, pair, label in order]
        summary = summarize(records, 'kernel_us')[0]
        self.assertEqual(summary['Ours']['samples'], 4)
        self.assertEqual(summary['Ours']['median'], 2.5)
        self.assertEqual(summary['paired_random_over_ours']['median'], 2)

    def test_trace_matching_rejects_missing_extra_and_wrong_geometry(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'trace.sqlite'
            with sqlite3.connect(path) as db:
                db.executescript('''
                    CREATE TABLE StringIds (id INTEGER, value TEXT);
                    INSERT INTO StringIds VALUES (1, 'jac_ChainSum_batch');
                    CREATE TABLE CUPTI_ACTIVITY_KIND_KERNEL (
                        start INTEGER, end INTEGER, shortName INTEGER,
                        gridX INTEGER, gridY INTEGER, gridZ INTEGER,
                        blockX INTEGER, blockY INTEGER, blockZ INTEGER);
                    INSERT INTO CUPTI_ACTIVITY_KIND_KERNEL
                        VALUES (1000, 5000, 1, 8, 1, 1, 128, 1, 1);
                ''')
            records = [{}]
            attach_kernel_times(path, records, 'jac_ChainSum_batch', 1000, 128)
            self.assertEqual(records[0]['kernel_us'], 4)
            for invalid in ([], [{}, {}]):
                with self.assertRaisesRegex(ValueError, 'Incomplete CUDA trace'):
                    attach_kernel_times(path, invalid, 'jac_ChainSum_batch', 1000, 128)
            with self.assertRaisesRegex(ValueError, 'geometry'):
                attach_kernel_times(path, [{}], 'jac_ChainSum_batch', 1000, 256)
            with self.assertRaisesRegex(ValueError, 'kernel'):
                attach_kernel_times(path, [{}], 'different_kernel', 1000, 128)


if __name__ == '__main__':
    unittest.main()
