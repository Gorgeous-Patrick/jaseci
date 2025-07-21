import random;
node Profile {
  has id: int;
}

node Tweet {
  has id: int;
  has content: str;
}

edge Follow {}
edge Post {}

walker LoadFeed {
  has visiting_neighbors: bool = False;
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
    print(here.id, here.content);
  }
}

with entry {
  nodes = [];
  NODE_NUM = 5;
  TWEET_NUM = 2;
  for i in range(NODE_NUM) {
    nodes.append(Profile(id = i));
    root ++> nodes[i];
    for j in range(TWEET_NUM) {
      nodes[i] +>:Post:+> Tweet(id=j, content="hello world");
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
  wlk = nodes[0] spawn LoadFeed();
}
