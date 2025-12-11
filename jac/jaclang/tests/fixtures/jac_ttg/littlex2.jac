import random;
import os;
node Profile {
    has id: int;
}

node Tweet {
    has id: int;
    has content_32: str;
}

edge Follow {}
edge Post {}

walker LoadFeed {
    has visiting_neighbors: bool = False;
    def get_byte_stream() {
        return struct.pack("<q", self.visiting_neighbors);
    }

    can load with Profile entry {
        if (not self.visiting_neighbors) {
            self.visiting_neighbors = True;
            visit [->:Post:->];
            visit [->:Follow:->];
        } else {
            visit [->:Post:->];
        }
    }

    can calc with Tweet entry {
        print(here.id, here.content_32);
    }
}

with entry {
    random.seed(0);
    nodes = [];
    NODE_NUM = int(os.environ.get("JAC_NODE_NUM"));
    EDGE_NUM = int(os.environ.get("JAC_EDGE_NUM"));
    if (EDGE_NUM is None) {
        exit(1);
    }
    TWEET_NUM = 2;
    for i in range(NODE_NUM) {
        nodes.append(Profile(id=i));
        root ++> nodes[i];
        for j in range(TWEET_NUM) {
            nodes[i] +>: Post :+> Tweet(
                id=NODE_NUM + TWEET_NUM * i + j, content_32="hello world"
            );
        }
    }

    available_edges = set();

    for i in range(NODE_NUM) {
        for j in range(NODE_NUM) {
            if (i == j) {
                continue;
            }
            available_edges.add((i, j));
        }
    }

    for i in range(EDGE_NUM) {
        (src, dst) = random.choice(list(available_edges));
        print(f"Adding edge from {src} to {dst}");
        nodes[src] +>: Follow :+> nodes[dst];
        available_edges.remove((src, dst));
    }

    for i in range(NODE_NUM) {
        wlk = LoadFeed();
        wlk = wlk spawn nodes[i];
    }
}
