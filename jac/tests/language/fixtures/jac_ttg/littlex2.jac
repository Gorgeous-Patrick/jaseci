import random;
import os;
import json;
import from util { append_to_json_list }
node Profile {
    has id: int;
}

node Tweet {
    has id: int;
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
        } else {
            visit [->:Post:->];
        }
    }

    can calc with Tweet entry {
        # print(here.id);
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
    TWEET_NUM = int(os.environ.get("JAC_TWEET_NUM"));
    for i in range(NODE_NUM) {
        nodes.append(Profile(id=i));
        root +>: Post :+> nodes[i];
        for j in range(TWEET_NUM) {
            nodes[i] +>: Post :+> Tweet(id=NODE_NUM + TWEET_NUM * i + j);
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
        nodes[src] +>: Follow :+> nodes[dst];
        available_edges.remove((src, dst));
    }
    ttg_list = [];

    for i in range(NODE_NUM) {
        wlk = LoadFeed();
        wlk = wlk spawn nodes[i];
        ttg_list.append(wlk.__ttg_dict__());
        append_to_json_list(
            "timer.json",
            {
                "JAC_NODE_NUM": NODE_NUM,
                "JAC_EDGE_NUM": EDGE_NUM,
                "JAC_TWEET_NUM": TWEET_NUM,
                "ttg_start_time": wlk.__ttg_start_time__.timestamp(),
                "ttg_end_time": wlk.__ttg_end_time__.timestamp(),
                "ttg_visited_num": len(wlk.__ttg_visited__),
                "traversal_start_time": wlk.__traversal_start_time__.timestamp(),
                "traversal_end_time": wlk.__traversal_end_time__.timestamp(),
                "traversal_visited_num": len(wlk.__traversal_visited__),

            }
        );
    }
    print(printgraph());
    json.dump(ttg_list, open("load_feed_ttg.json", "w"), indent=2);
}
