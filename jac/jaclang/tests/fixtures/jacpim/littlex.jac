import random;
import from analytical.data_prep {download_and_cache, get_subgraph}
import os;
import from jaclang.runtimelib.machine {JacMachine}

node Profile {
  has id: int;
  has tweets: list[str];
}

edge Follow {}

walker LoadFeed{
  has visiting_neighbors: bool = False;
  can run with Profile entry  {
    print(f"visit ID {here.id}");
    if (not self.visiting_neighbors) {
        self.visiting_neighbors = True;
        visit [->:Follow:->];
    } 
    # Calculate the cosine similarity and report back to CPU.
  }
}

with entry {
  nodes = [];
  NODE_NUM = 10;
  for i in range(NODE_NUM) {
    nodes.append(Profile(id = i, tweets = []));
    root ++> nodes[i];
  }

  for i in range(NODE_NUM) {
    for j in range(NODE_NUM) {
      if (i == j) {
        continue;
      }
      if ((random.uniform(0, 1)) <= 0.5){
        nodes[i] +>:Follow:+> nodes[j];
      }
    }
  }
  wlk = nodes[0] spawn LoadFeed();
}
