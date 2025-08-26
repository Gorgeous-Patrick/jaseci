import random;
node Data {
   has id: int; 
}

walker Finder {
    can up with Data entry {
        if (len([-->]) == 0) {
            print(f"Found Node {here.id}");
        } else {
            visit [-->];
        }
    }
}

def random_tree(nodes: list) -> None {
    edges = [];
    for i in range(1, len(nodes)) {
        u = nodes[i];
        v = nodes[i // 2];
        u ++> v;
        print(f"{u.id} -> {v.id}"); }
}



with entry {
    NUM_NODES_PER_TREE = 128;
    NUM_TREE = 40;
    all_nodes = [];
    for i in range(NUM_TREE) {
        nodes = [Data(id = id) for id in range(i * NUM_NODES_PER_TREE, (i + 1) * NUM_NODES_PER_TREE)];
        for node in nodes {
            root ++> node;
        }
        random_tree(nodes);
        all_nodes.extend(nodes);
    }
    print(f"Spawn on node {all_nodes[NUM_NODES_PER_TREE * NUM_TREE - 1].id}");
    wlk = all_nodes[NUM_NODES_PER_TREE * NUM_TREE - 1] spawn Finder();
}
