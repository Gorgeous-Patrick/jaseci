
import random;
import from analytical.data_prep {download_and_cache, get_subgraph}
import os;

node Page {
  has id: int;
  has score: float = 0;
  has new_score: float = 0;
}

edge HyperLink {}

walker PageRank{
  has collected_score: float | None = None;
  can run with Page entry  {
    print(f"visit ID {here.id}");
    if (self.collected_score is None) {
      if (len([->:HyperLink:->]) == 0) {
        return;
      }
      self.collected_score = here.score / len([->:HyperLink:->]);
      visit [->:HyperLink:->];
    } else {
      here.new_score += self.collected_score;
    }
  }
}

with entry {
  
  nodes = [];
  NODE_NUM = 20;
  for i in range(NODE_NUM) {
    nodes.append(Page(id = i));
    root ++> nodes[i];
  }

  for i in range(NODE_NUM) {
    for j in range(NODE_NUM) {
      if (i == j) {
        continue;
      }
      if ((random.uniform(0, 1)) <= 0.5){
        nodes[i] +>:HyperLink:+> nodes[j];
      }
    }
  }
  wlk = nodes[0] spawn PageRank();
}
