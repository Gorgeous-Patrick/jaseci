from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl


class DataCollector(_jl.Walker):
    collected: list = _jl.field(factory=lambda: [])

    @_jl.entry
    def process(self, here: _jl.Root) -> None:
        _jl.report("Processing started")
        _jl.report(42 * 2)
        _jl.report(self.collected)
        _jl.report({"status": "complete", "count": len(self.collected)})


w = DataCollector()
_jl.spawn(w, _jl.root())
