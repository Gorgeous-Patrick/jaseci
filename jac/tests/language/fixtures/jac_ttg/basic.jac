edge BasicEdge {}

node BFSNode {
    has id: int;
    has jac_node_size: int = 8;
}

edge JunkEdge {}

walker BFS {
    has visited_512: list[bool] = [False] * 512;

    can run with BFSNode entry {
        if (self.visited_512[here.id]) {
            return;
        }
        self.visited_512[here.id] = True;
        visit [->:BasicEdge:->];
        visit [->:JunkEdge:->];
    }
}
def create_node() -> list[str] {
    nodes = [BFSNode(id=0), BFSNode(id=1), BFSNode(id=2), BFSNode(id=3), BFSNode(id=4)];
    junk = BFSNode(id=5);  # To ensure IDs are not reused
    root +>: BasicEdge :+> nodes[0];
    nodes[0] +>: BasicEdge :+> nodes[1];
    nodes[0] +>: BasicEdge :+> nodes[2];
    nodes[1] +>: BasicEdge :+> nodes[3];
    nodes[1] +>: BasicEdge :+> nodes[4];
    result = [];
    for n in nodes {
        result.append(str(n.__jac__.id));
    }
    return result;
}

with entry {
    node_ids = create_node();
    import os;
    os.environ["JAC_PREFETCH"] = "1";
    root spawn BFS();
    print(node_ids);
}
