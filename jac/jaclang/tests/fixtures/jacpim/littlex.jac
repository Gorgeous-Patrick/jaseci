import from analytical.data_prep {download_and_cache, get_subgraph}
import os;
import from jaclang.runtimelib.machine {JacMachine}

node People {
  has id: int;
}

edge Follow {}

walker LoadFeed{
  has visiting_neighbors: bool = False;
  can run with People entry  {
    print(f"visit ID {here.id}");
    if (not self.visiting_neighbors) {
        self.visiting_neighbors = True;
        visit [->:Follow:->];
    } else {
        # Calculate the stuff
    }
  }
}

with entry {
  
  SNAP_URL = "https://snap.stanford.edu/data/twitter-2010.txt.gz";
  DATA_DIR = "snap_data";
  RAW_FILE = os.path.join(DATA_DIR, "twitter.txt.gz");
  EXTRACTED_FILE = os.path.join(DATA_DIR, "twitter.txt");
  SUBGRAPH_FILE = os.path.join(DATA_DIR, "twitter-subgraph.txt");

    download_and_cache(RAW_FILE, EXTRACTED_FILE, SNAP_URL, DATA_DIR);

    subgraph = get_subgraph(EXTRACTED_FILE, SUBGRAPH_FILE, target_size=300, limit=10000, small=True);
    jac_nodes = {};
    for node in subgraph.nodes() {
      jac_nodes[node] = People(id = node);
      root ++> jac_nodes[node];
    }
    for edge in subgraph.edges() {
      jac_nodes[edge[0]] +>:Follow:+> jac_nodes[edge[1]];
    }
    walkers = [];
    for node in subgraph.nodes() {
      walkers.append(jac_nodes[node] spawn LoadFeed());
    }
}
