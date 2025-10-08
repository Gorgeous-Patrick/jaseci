from __future__ import annotations
from jaclang.lib import Root, Walker, disengage, on_entry, report, root, spawn

class Reporter(Walker):

    @on_entry
    def process(self, here: Root) -> None:
        report(42)
        report('hello')
        report(10 + 20)
        x = 100
        report(x)
        report([1, 2, 3])
        report({'key': 'value', 'number': 123})
        report({'result': 5 * 10, 'status': 'ok'})
        disengage(self)
        return
w = Reporter()
spawn(root(), w)
