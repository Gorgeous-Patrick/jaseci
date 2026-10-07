"""Regression tests for prediction-only seed compression and batch bindings."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from compare_named_layouts import schemas_and_modules, memory_context
from bounded import build_inputs, planning_bindings, axis_heads, bind


class BoundedTests(unittest.TestCase):
    def test_compressed_prediction_matches_all_lanes_and_actual_events(self):
        from jaclang.runtime import gpu_cursors
        from jaclang.runtime.runtime import JacRuntime
        schemas,modules=schemas_and_modules(['Dot']);mod=modules['Dot']
        with memory_context():
            for m,k,n in ((4,4,4),(3,5,2),(1,7,3),(5,1,1)):
                heads=build_inputs(mod,m,k,n,2)
                walkers,compressed=planning_bindings(mod,heads)
                full=[dict(a=heads[0][i],b=heads[1][j]) for i in range(m) for j in range(n)]
                for layout in ('current','predicted'):
                    small=gpu_cursors.pack_cursors(schemas['Dot'],walkers,compressed,1,k+1,
                        layout=layout,prediction_budget=max(m*k,n*k))
                    complete=gpu_cursors.pack_cursors(schemas['Dot'],[mod.Dot() for _ in full],full,1,k+1,
                        layout=layout,prediction_budget=max(m*k,n*k))
                    self.assertEqual([id(v) for v in small.nodes],[id(v) for v in complete.nodes])
                    self.assertEqual(small.buffers.arrays()[:4],complete.buffers.arrays()[:4])
                    axes=axis_heads(small.buffers,m,n)
                    collected=[]
                    for start in range(0,m*n,3):
                        batch=bind(small.buffers,axes,start,min(3,m*n-start),n)
                        expected=[JacRuntime.spawn(binding,mod.Dot()).total
                                  for binding in full[start:start+len(batch.results)]]
                        values,status=gpu_cursors.run_jit(schemas['Dot'].cursor_spec,batch)
                        self.assertEqual(status,[0]*len(expected))
                        self.assertEqual(values[0],expected)
                        collected.extend(values[0])
                    self.assertEqual(collected,[k*(i+1)*(j+1) for i in range(m) for j in range(n)])


if __name__=='__main__':unittest.main()
