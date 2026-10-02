"""Create demo tree data; node i has children 2*i+1 and 2*i+2.

Graph construction runs on the CPU. All query walkers share this same tree.
"""

import from subtree_query { Item, Child }

def make_tree(amounts: list[int], alerts: list[bool]) -> list[Item] {
    if not amounts or len(amounts) != len(alerts) {
        raise ValueError("Tree amounts and alerts must have matching nonzero lengths");
    }
    nodes = [Item(amount=value, alert=flag) for (value, flag) in zip(amounts, alerts)];
    for child in range(1, len(nodes)) {
        nodes[(child - 1) // 2] +>:Child():+> nodes[child];
    }
    return nodes;
}
