import data_prep;
import os;

import from jaclang.runtimelib.machine {JacMachine}
node Profile {
  has id: int;
  def get_byte_stream() {
    res = struct.pack("<Q", self.id);
    return res;
  }
  static def get_type_def() {
    return "uint64_t id;";
  }
}

node Tweet {
  has id: int;
  has content_32: str;

  def get_byte_stream() {
    res = struct.pack("<Q", self.id) + struct.pack("<32s", self.content_32.encode('utf-8'));
    return res;
  }
  static def get_type_def() {
    return "uint64_t id; char content_32[32];";
  }
}

edge Follow {}
edge Post {}

walker LoadFeed {
  has visiting_neighbors: bool = False;
  def get_type_def() {
    return "uint64_t visiting_neighbors;";
  }

  def get_byte_stream() {
    return struct.pack("<q", self.visiting_neighbors);
  }
  can load with Profile entry {
    if (not self.visiting_neighbors) {
      self.visiting_neighbors = True;
      visit [->:Post:->];
      visit [->:Follow:->];
    }
    else {
      visit [->:Post:->];
    }
  }

  can calc with Tweet entry {
    print(here.id, here.content_32);
  }

  def get_impl_load_on_Profile() {
    return """
    if (walker->visiting_neighbors == false) {
      walker->visiting_neighbors = true;
    for (uint32_t i = 0; i < edge_num; i++) {
      push_new_element_to_container(1);
      }
    } else {
    push_new_element_to_container(0);
    push_new_element_to_container(0);
    }
    """;
  }
  def get_impl_calc_on_Tweet() {
    # return """printf("%d %s\\n", here.id, here.content_32);""";
    return "";
  }
  def get_byte_stream() {
    return struct.pack("<q", self.visiting_neighbors);
  }
}

with entry {
  SNAP_URL = "https://snap.stanford.edu/data/twitter-2010.txt.gz";
  DATA_DIR = "snap_data";
  RAW_FILE = os.path.join(DATA_DIR, "twitter.txt.gz");
  EXTRACTED_FILE = os.path.join(DATA_DIR, "twitter.txt");
  SUBGRAPH_FILE = os.path.join(DATA_DIR, "twitter-subgraph.txt");
  TWEET_NUM = 2;

  data_prep.download_and_cache(RAW_FILE, EXTRACTED_FILE, SNAP_URL, DATA_DIR);
  G = data_prep.get_subgraph(EXTRACTED_FILE, SUBGRAPH_FILE, target_size=25, limit=10000, max_degree=10);
  nodes = {int(n): Profile(id=int(n)) for n in G.nodes()};
  for n in nodes.values() {
    root ++> n;
    for j in range(TWEET_NUM) {
      n +>:Post:+> Tweet(id=j, content_32="hello world");
    }
  }
  print(nodes);
  for e in G.edges(){
    u = int(e[0]);
    v = int(e[1]);
    print(u, "->", v);
    nodes[u] +>:Follow:+> nodes[v];
  }
  JacMachine.jacpim_init();

  wlk = LoadFeed();
  JacMachine.jacpim_spawn(wlk, nodes[0]);

  JacMachine.jacpim_start();
}