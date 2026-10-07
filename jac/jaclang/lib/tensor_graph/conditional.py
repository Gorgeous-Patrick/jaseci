"""Cond dependency slicing and bookkeeping; no primitive numerical dispatch.

One non-nested Cond in a pure DAG. Shared pure work intentionally runs before
selection. Branch-result edges are lazy references, not eager operand deliveries.
"""
from collections import Counter
from typing import Any


def analyze(model) -> Any:
    from .runtime import Cond, Input, Parameter, Constant
    names = [n for n, op in model.ops.items() if type(op) is Cond]
    if not names:
        return None
    if len(names) != 1:
        raise ValueError('Only one Cond supported; nesting/multiple Cond unsupported')
    name = names[0]
    plan = model.plan
    sources, order = plan['sources'], plan['order']

    def closure(root):
        seen = set()
        def walk(n):
            if n in seen:
                return
            seen.add(n)
            for producer in sources[n].values():
                walk(producer)
        walk(root)
        return seen

    c, t, f = (closure(sources[name][port]) for port in
               ('condition', 'true_result', 'false_result'))
    if name in c | t | f:
        raise ValueError('Cond cycle/nesting unsupported')
    shared = t & f
    pre = c | shared
    # Boundary leaves (including exclusive weights) are explicit tensor operands.
    pre |= {n for n in order if type(model.ops[n]) in (Input, Parameter, Constant)}
    pre = set().union(*(closure(n) for n in pre))
    tr, fr = t - pre, f - pre
    for region in (tr, fr):
        for n in region:
            for consumer in plan['consumers'][n]:
                if consumer not in region and consumer != name:
                    raise ValueError('Exclusive branch value escapes Cond region: ' + n)
            if n == model.output_name:
                raise ValueError('Exclusive branch cannot be selected graph output')
    if name not in closure(model.output_name):
        raise ValueError('Selected graph output must depend on Cond')
    post = set(order) - pre - tr - fr - {name}
    # Unrelated pure calculations can run afterward; no branch leakage permitted.
    boundary = {producer for region in (tr, fr) for n in region
                for producer in sources[n].values() if producer not in region}
    for port in ('true_result', 'false_result'):
        root = sources[name][port]
        if root in pre:
            boundary.add(root)
    return dict(node=name, condition_root=sources[name]['condition'],
                true_root=sources[name]['true_result'], false_root=sources[name]['false_result'],
                condition_slice=[n for n in order if n in c], shared_slice=[n for n in order if n in shared],
                pre=[n for n in order if n in pre], true_region=[n for n in order if n in tr],
                false_region=[n for n in order if n in fr], post=[n for n in order if n in post],
                operands=[n for n in order if n in boundary],
                contract='Condition closure and shared pure dependency closure run before selection; only selected exclusive region executes. Boundary leaves are precomputed operands.',
                liveness_note='Static DAG liveness models all branches in metadata order, not selected-path scheduling or a memory upper bound; runtime releases use selected-path consumer counts.')


class Execution:
    """Drive the Jac walker through analyzed real dependencies, retaining handles."""
    def __init__(self, model, capture):
        self.model, self.info = model, model.plan['conditional']
        exclusive = set(self.info['true_region'] + self.info['false_region'])
        if exclusive.intersection(capture):
            raise ValueError('Capturing exclusive branch nodes is unsupported')
        self.queue = list(self.info['pre'])
        self.selected = None
        self.selected_port = None
        self.values = {}
        self.remaining = None
        self.handle_identity = []

    def next_node(self):
        if not self.queue and self.selected is None:
            # Python Jac traversal needs one scalar predicate read. On CUDA this
            # synchronizes once per Cond; FX/Inductor retain device control flow.
            predicate = bool(self.values[self.info['condition_root']].item())
            self.selected_port = 'true_result' if predicate else 'false_result'
            self.selected = self.info['true_root'] if predicate else self.info['false_root']
            region = self.info['true_region'] if predicate else self.info['false_region']
            self.queue = list(region) + [self.info['node']] + list(self.info['post'])
            executed = self.info['pre'] + self.queue
            self.remaining = Counter()
            for n in executed:
                self.remaining.update(self.source_names(n))
            for n in self.info['pre']:
                self.remaining.subtract(self.source_names(n))
            self.release_unused()
        return self.queue.pop(0) if self.queue else None

    def source_names(self, name):
        if name == self.info['node']:
            return [self.info['condition_root'], self.selected]
        return list(self.model.plan['sources'][name].values())

    def inputs(self, name):
        if name == self.info['node']:
            sources = {'condition': self.info['condition_root'], self.selected_port: self.selected}
        else:
            sources = self.model.plan['sources'][name]
        result = {}
        for port, producer in sources.items():
            result[port] = self.values[producer]
            self.handle_identity.append(dict(producer=producer, consumer=name, port=port,
                                             same_object=result[port] is self.values[producer]))
        return result

    def release_unused(self):
        released = []
        for name in list(self.values):
            if self.remaining[name] == 0 and name != self.model.output_name:
                del self.values[name]
                self.model.ops[name].output = None
                released.append(name)
        return sorted(released)

    def finish(self, name, value):
        self.values[name] = value
        released = []
        if self.remaining is not None:
            self.remaining.subtract(self.source_names(name))
            released = self.release_unused()
        return dict(node=name, release=released, live_after=sorted(self.values),
                    note='Selected-path liveness; pre-selection boundary handles retained until predicate read')
