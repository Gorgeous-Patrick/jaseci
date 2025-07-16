import from analytical.data_prep {download_and_cache, get_subgraph}
import os;
import from jaclang.runtimelib.machine {JacMachine}

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
  
  SNAP_URL = "https://snap.stanford.edu/data/wiki-topcats.txt.gz";
  DATA_DIR = "snap_data";
  RAW_FILE = os.path.join(DATA_DIR, "wiki-topcats.txt.gz");
  EXTRACTED_FILE = os.path.join(DATA_DIR, "wiki-topcats.txt");
  SUBGRAPH_FILE = os.path.join(DATA_DIR, "wiki-topcats-subgraph.txt");

    download_and_cache(RAW_FILE, EXTRACTED_FILE, SNAP_URL, DATA_DIR);

    subgraph = get_subgraph(EXTRACTED_FILE, SUBGRAPH_FILE, target_size=300, limit=10000, small=True);
    jac_nodes = {};
    for node in subgraph.nodes() {
      jac_nodes[node] = Page(id = node, score = 1/len(subgraph.nodes()));
      root ++> jac_nodes[node];
    }
    for edge in subgraph.edges() {
      jac_nodes[edge[0]] +>:HyperLink:+> jac_nodes[edge[1]];
    }
    walkers = [];
    for node in subgraph.nodes() {
      walkers.append(jac_nodes[node] spawn PageRank());
    }
    JacMachine.mapping(walkers);
}
