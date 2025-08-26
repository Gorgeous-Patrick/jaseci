import random;
import from jaclang.runtimelib.machine {JacMachine}
node BFSNode {
  has id:int;
}


walker BFS {
  has visited_500: list[int] = [];
  can run with BFSNode entry {
    if (here.id in self.visited_500) {
      return;
    }
    print(here.id);
    self.visited_500.append(here.id);
    visit [-->];
  }
}


with entry {
nodes = [];
NODE_NUM = 500;
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
# r = BFSNode(id = 0);
# n1 = BFSNode(id = 1);
# n2 = BFSNode(id = 2);
# n3 = BFSNode(id = 3);
# root ++> r;
# r ++> n1;
# n1 ++> r;
# r ++> n2;
# n1 ++> n2;
# r ++> n3;
# wlk = r spawn BFS();
}
