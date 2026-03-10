import from basic {BasicEdge, BFSNode};
walker BFS {
    has visited_512: list[bool] = [False] * 512;

    can run with BFSNode entry {
        if (self.visited_512[here.id]) {
            return;
        }
        self.visited_512[here.id] = True;
        visit [->:BasicEdge:->];
    }
}
