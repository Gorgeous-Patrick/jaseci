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
  for i in range(100) {
    nodes.append(BFSNode(id = i));
    root ++> nodes[i];
  }

  for i in range(100) {
    for j in range(100) {
      if (i == j) {
        continue;
      }
      if ((random.randint(0, 1)) == 0){
        nodes[i] ++> nodes[j];
      }
    }
  }
  wlk = nodes[0] spawn BFS();
  JacMachine.mapping([wlk]);
}