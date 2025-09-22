import random;
import struct;
import from jaclang.runtimelib.machine {JacMachine}
node Start {
  has id: int = 0;
  def get_byte_stream() {
    res = struct.pack("<q", self.id);
    return res;
  }
  static def get_type_def() {
    return "uint64_t id;";
  }
}
node Profile {
  has id: int;
  def get_byte_stream() {
    res = struct.pack("<q", self.id);
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
    res = struct.pack("<q", self.id) + struct.pack("<32s", self.content_32.encode('utf-8'));
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
  can boot with Start entry {
    # print("Starting load feed from user ", here.id);
    # visit [->:Profile:->];
    JacMachine.par_visit(self, LoadFeed(), [-->]);
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
    if (!self->visiting_neighbors) {
      self->visiting_neighbors = true;
      visit(ctx, me, "Post", "->", NULL);
      visit(ctx, me, "Follow", "->", NULL);
    } else {
      visit(ctx, me, "Post", "->", NULL);
    }
    """;
  }
  def get_impl_calc_on_Tweet() {
    return """printf("%d %s\\n", here.id, here.content_32);""";
  }
  def get_byte_stream() {
    return struct.pack("<q", self.visiting_neighbors);
  }
}

with entry {
  nodes = [];
  NODE_NUM = 256;
  TWEET_NUM = 2;
  for i in range(NODE_NUM) {
    nodes.append(Profile(id = i));
    root ++> nodes[i];
    for j in range(TWEET_NUM) {
      nodes[i] +>:Post:+> Tweet(id=j, content_32="hello world");
    }
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
  start_node = Start(id=0);
  root ++> start_node;
  for i in range(max(NODE_NUM // 10, 30)){

    start_node ++> nodes[i];
  }
  wlk = LoadFeed();
  JacMachine.start(wlk, start_node);
  wlk = start_node spawn wlk;
  JacMachine.end(wlk);
}
