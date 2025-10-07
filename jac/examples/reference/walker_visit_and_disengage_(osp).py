"""Walker visit and disengage (OSP): Graph traversal control with visit and disengage statements."""
from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Person(_jl.Node):
    name: str

class Friend(_jl.Edge):
    pass

class Colleague(_jl.Edge):
    strength: int

class BasicVisitor(_jl.Walker):

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('BasicVisitor: visiting outgoing edges')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def visit_person(self, here: Person) -> None:
        print(f'BasicVisitor: at {here.name}')

class VisitWithElse(_jl.Walker):

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('VisitWithElse: visiting with else clause')
        if not _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit())):
            print('VisitWithElse: no outgoing edges from root')

    @_jl.entry
    def visit_person(self, here: Person) -> None:
        print(f'VisitWithElse: at {here.name}')
        if not _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit())):
            print(f'VisitWithElse: leaf node - {here.name}')

class DirectVisit(_jl.Walker):
    target: Person

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('DirectVisit: going directly to target')
        _jl.visit(self, self.target)

    @_jl.entry
    def at_target(self, here: Person) -> None:
        print(f'DirectVisit: arrived at {here.name}')

class TypedVisit(_jl.Walker):

    @_jl.entry
    def start(self, here: Person) -> None:
        print(f'TypedVisit: at {here.name}, visiting Friend edges only')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out(edge=lambda i: isinstance(i, Friend)).visit()))

    @_jl.entry
    def visit_friend(self, here: Person) -> None:
        print(f'TypedVisit: visited friend {here.name}')

class FilteredVisit(_jl.Walker):

    @_jl.entry
    def start(self, here: Person) -> None:
        print(f'FilteredVisit: visiting strong colleagues from {here.name}')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out(edge=lambda i: isinstance(i, Colleague) and i.strength > 5).visit()))

    @_jl.entry
    def visit_colleague(self, here: Person) -> None:
        print(f'FilteredVisit: visited colleague {here.name}')

class BasicDisengage(_jl.Walker):

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('BasicDisengage: starting traversal')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def visit_person(self, here: Person) -> None:
        print(f'BasicDisengage: at {here.name}')
        if here.name == 'Bob':
            print('BasicDisengage: found Bob, disengaging')
            _jl.disengage(self)
            return
        print(f'BasicDisengage: continuing from {here.name}')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class ConditionalDisengage(_jl.Walker):
    max_visits: int = 2
    visit_count: int = 0

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('ConditionalDisengage: starting')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def count_visits(self, here: Person) -> None:
        self.visit_count += 1
        print(f'ConditionalDisengage: visit {self.visit_count} at {here.name}')
        if self.visit_count >= self.max_visits:
            print('ConditionalDisengage: max visits reached, disengaging')
            _jl.disengage(self)
            return
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class SearchWalker(_jl.Walker):
    target_name: str
    found: bool = False

    @_jl.entry
    def search(self, here: _jl.Root) -> None:
        print(f'SearchWalker: searching for {self.target_name}')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def check(self, here: Person) -> None:
        print(f'SearchWalker: checking {here.name}')
        if here.name == self.target_name:
            print(f'SearchWalker: found {here.name}!')
            self.found = True
            _jl.disengage(self)
            return
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class MultiVisit(_jl.Walker):
    visit_phase: int = 1

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('MultiVisit: phase 1 - visit all outgoing')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def phase_one(self, here: Person) -> None:
        if self.visit_phase == 1:
            print(f'MultiVisit: phase 1 at {here.name}')
            self.visit_phase = 2
            _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def phase_two(self, here: Person) -> None:
        if self.visit_phase == 2:
            print(f'MultiVisit: phase 2 at {here.name}')

class ImmediateStop(_jl.Walker):

    @_jl.entry
    def self_destruct(self, here: _jl.Root) -> None:
        print('ImmediateStop: before disengage')
        _jl.disengage(self)
        return
        print('ImmediateStop: after disengage (never printed)')

class ComplexTraversal(_jl.Walker):
    depth: int = 0
    max_depth: int = 2
    nodes_visited: list[str] = _jl.field(factory=lambda: [])

    @_jl.entry
    def start(self, here: _jl.Root) -> None:
        print('ComplexTraversal: starting from root')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.entry
    def traverse(self, here: Person) -> None:
        self.depth += 1
        self.nodes_visited.append(here.name)
        print(f'ComplexTraversal: depth {self.depth} at {here.name}')
        if self.depth >= self.max_depth:
            print('ComplexTraversal: max depth reached, disengaging')
            _jl.disengage(self)
            return
        if not _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit())):
            print(f'ComplexTraversal: leaf node at {here.name}')
alice = Person(name='Alice')
bob = Person(name='Bob')
charlie = Person(name='Charlie')
diana = Person(name='Diana')
eve = Person(name='Eve')
_jl.connect(left=_jl.root(), right=alice)
_jl.connect(left=alice, right=bob)
_jl.connect(left=alice, right=charlie)
_jl.connect(left=bob, right=diana)
_jl.connect(left=charlie, right=eve)
_jl.connect(left=alice, right=bob, edge=Friend)
_jl.connect(left=alice, right=charlie, edge=Colleague(strength=7))
_jl.connect(left=alice, right=diana, edge=Colleague(strength=3))
print('=== Basic Visit ===')
_jl.spawn(_jl.root(), BasicVisitor())
print('\n=== Visit with Else ===')
_jl.spawn(_jl.root(), VisitWithElse())
print('\n=== Direct Visit ===')
_jl.spawn(_jl.root(), DirectVisit(target=charlie))
print('\n=== Typed Visit ===')
_jl.spawn(alice, TypedVisit())
print('\n=== Filtered Visit ===')
_jl.spawn(alice, FilteredVisit())
print('\n=== Basic Disengage ===')
_jl.spawn(_jl.root(), BasicDisengage())
print('\n=== Conditional Disengage ===')
_jl.spawn(_jl.root(), ConditionalDisengage())
print('\n=== Search Walker ===')
w = _jl.spawn(_jl.root(), SearchWalker(target_name='Charlie'))
print(f'Found: {w.found}')
print('\n=== Multi Visit ===')
_jl.spawn(_jl.root(), MultiVisit())
print('\n=== Immediate Stop ===')
_jl.spawn(_jl.root(), ImmediateStop())
print('\n=== Complex Traversal ===')
ct = _jl.spawn(_jl.root(), ComplexTraversal())
print(f'Nodes visited: {ct.nodes_visited}')
