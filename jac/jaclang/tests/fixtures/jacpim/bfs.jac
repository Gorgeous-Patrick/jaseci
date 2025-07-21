import random;
import from jaclang.runtimelib.machine {JacMachine}
node BFSNode {
  has id:int;
}


walker BFS {
  has visited: list[int] = [];
  can run with BFSNode entry {
    if (here.id in self.visited) {
      return;
    }
    print(here.id);
    self.visited.append(here.id);
    visit [-->];
  }
}


with entry {
  nodes = [];
  NODE_NUM = 5;
  for i in range(NODE_NUM) {
    nodes.append(BFSNode(id = i));
    root ++> nodes[i];
  }

  for i in range(NODE_NUM) {
    for j in range(NODE_NUM) {
      if (i == j) {
        continue;
      }
      if ((random.uniform(0, 1)) <= 0.5){
        nodes[i] ++> nodes[j];
      }
    }
  }
  wlk = nodes[0] spawn BFS();
}
