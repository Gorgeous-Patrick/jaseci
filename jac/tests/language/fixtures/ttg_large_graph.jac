"""TTG large-graph integration test fixture.

Builds a DAG with 23 non-root nodes across 3 node types (Server, Database,
Cache) connected by 3 edge types (HttpEdge, DbEdge, CacheEdge).
Three walkers with different edge-filter strategies are run and their
actual traversal is compared with TTG predictions.

Topology (all edges are directed, no cycles):

  root ──HttpEdge──> s1 ──HttpEdge──> s2 ──HttpEdge──> s3 ──HttpEdge──> s4
                      │                │                │                │
                    DbEdge           DbEdge           DbEdge          DbEdge
                      v                v                v                v
                     d1 ──DbEdge──> d2 ──DbEdge──> d3 ──DbEdge──> d4
                      │                │                │                │
                  CacheEdge        CacheEdge        CacheEdge       CacheEdge
                      v                v                v                v
                     c1               c2               c3               c4
                      │
                  HttpEdge
                      v
                     s5 ──HttpEdge──> s6 ──HttpEdge──> s7 ──HttpEdge──> s8
                                       │                │
                                     DbEdge           DbEdge
                                       v                v
                                      d5               d6 ──DbEdge──> d7
                                       │                │
                                   CacheEdge        CacheEdge
                                       v                v
                                      c5               c6

Nodes: 8 Servers (s1-s8) + 7 Databases (d1-d7) + 6 Caches (c1-c6) = 21,
       plus root = 22 (root excluded from typed counts).
       Adding c7, c8: c5 ──CacheEdge──> c7, c6 ──CacheEdge──> c8.
       Total non-root: 8S + 7D + 8C = 23 nodes.
"""

import os;
import from jaclang.jac0core.ttg { JacTTGGenerator, TypedWalkerState }

# ── Edge types ────────────────────────────────────────────────────────────────
edge HttpEdge {}
edge DbEdge {}
edge CacheEdge {}

# ── Node types ────────────────────────────────────────────────────────────────
node Server {
    has name: str;
}

node Database {
    has name: str;
}

node Cache {
    has name: str;
}

# ── Walker 1: HttpCrawler — follows only HttpEdge from Root & Server ─────────
walker HttpCrawler {
    has visited: list[str] = [];

    can enter_root with Root entry {
        visit [->:HttpEdge:->];
    }

    can visit_server with Server entry {
        self.visited.append(here.name);
        visit [->:HttpEdge:->];
    }
}

# ── Walker 2: ServiceDbCrawler — follows HttpEdge + DbEdge from Server,
#              DbEdge from Database ───────────────────────────────────────────
walker ServiceDbCrawler {
    has visited: list[str] = [];

    can enter_root with Root entry {
        visit [->:HttpEdge:->];
    }

    can visit_server with Server entry {
        self.visited.append(here.name);
        visit [->:HttpEdge:->];
        visit [->:DbEdge:->];
    }

    can visit_db with Database entry {
        self.visited.append(here.name);
        visit [->:DbEdge:->];
    }
}

# ── Walker 3: FullCrawler — follows all edge types from all node types ───────
walker FullCrawler {
    has visited: list[str] = [];

    can enter_root with Root entry {
        visit [->:HttpEdge:->];
    }

    can visit_server with Server entry {
        self.visited.append(here.name);
        visit [->:HttpEdge:->];
        visit [->:DbEdge:->];
    }

    can visit_db with Database entry {
        self.visited.append(here.name);
        visit [->:DbEdge:->];
        visit [->:CacheEdge:->];
    }

    can visit_cache with Cache entry {
        self.visited.append(here.name);
        visit [->:CacheEdge:->];
        visit [->:HttpEdge:->];
    }
}

# ── Construct nodes ──────────────────────────────────────────────────────────
glob s1 = Server(name="s1"), s2 = Server(name="s2"),
     s3 = Server(name="s3"), s4 = Server(name="s4"),
     s5 = Server(name="s5"), s6 = Server(name="s6"),
     s7 = Server(name="s7"), s8 = Server(name="s8");

glob d1 = Database(name="d1"), d2 = Database(name="d2"),
     d3 = Database(name="d3"), d4 = Database(name="d4"),
     d5 = Database(name="d5"), d6 = Database(name="d6"),
     d7 = Database(name="d7");

glob c1 = Cache(name="c1"), c2 = Cache(name="c2"),
     c3 = Cache(name="c3"), c4 = Cache(name="c4"),
     c5 = Cache(name="c5"), c6 = Cache(name="c6"),
     c7 = Cache(name="c7"), c8 = Cache(name="c8");

# ── Wire the graph (DAG, no cycles) ─────────────────────────────────────────
with entry {
    # Top-level server chain (HttpEdge)
    root +>: HttpEdge :+> s1;
    s1 +>: HttpEdge :+> s2;
    s2 +>: HttpEdge :+> s3;
    s3 +>: HttpEdge :+> s4;

    # Server → Database (DbEdge)
    s1 +>: DbEdge :+> d1;
    s2 +>: DbEdge :+> d2;
    s3 +>: DbEdge :+> d3;
    s4 +>: DbEdge :+> d4;

    # Database chain (DbEdge)
    d1 +>: DbEdge :+> d2;
    d2 +>: DbEdge :+> d3;
    d3 +>: DbEdge :+> d4;

    # Database → Cache (CacheEdge)
    d1 +>: CacheEdge :+> c1;
    d2 +>: CacheEdge :+> c2;
    d3 +>: CacheEdge :+> c3;
    d4 +>: CacheEdge :+> c4;

    # Cross-layer: Cache → Server (HttpEdge), no cycles
    c1 +>: HttpEdge :+> s5;

    # Lower section
    s5 +>: HttpEdge :+> s6;
    s6 +>: HttpEdge :+> s7;
    s7 +>: HttpEdge :+> s8;
    s6 +>: DbEdge :+> d5;
    s7 +>: DbEdge :+> d6;
    d6 +>: DbEdge :+> d7;
    d5 +>: CacheEdge :+> c5;
    d6 +>: CacheEdge :+> c6;
    c5 +>: CacheEdge :+> c7;
    c6 +>: CacheEdge :+> c8;
}

# ── Helpers ──────────────────────────────────────────────────────────────────
def count_ttg_nodes(state: TypedWalkerState) -> int {
    n = 1;
    for ch in state.children {
        n = n + count_ttg_nodes(ch);
    }
    return n;
}

def collect_ttg_node_types(state: TypedWalkerState, tm: dict) -> list[str] {
    """BFS over TTG tree, returning list of type names (excluding Root)."""
    result: list[str] = [];
    queue = [state];
    while queue {
        s = queue.pop(0);
        t = tm.get(s.nd);
        if t is not None and t.__name__ != "Root" {
            result.append(t.__name__);
        }
        for ch in s.children {
            queue.append(ch);
        }
    }
    return result;
}

def max_depth(state: TypedWalkerState) -> int {
    if not state.children {
        return state.depth;
    }
    return max(max_depth(ch) for ch in state.children);
}

# ── Verify walkers ───────────────────────────────────────────────────────────
glob r = root;

with entry {
    # Walker 1: HttpCrawler — only traverses HttpEdge from Server entry
    w1 = HttpCrawler() spawn root;
    print("w1_visited", sorted(w1.visited));
}

with entry {
    # Walker 2: ServiceDbCrawler — traverses HttpEdge+DbEdge from Server, DbEdge from Database
    w2 = ServiceDbCrawler() spawn root;
    print("w2_visited", sorted(w2.visited));
}

with entry {
    # Walker 3: FullCrawler — traverses all edge types from all node types
    w3 = FullCrawler() spawn root;
    print("w3_visited", sorted(w3.visited));
}

# ── Root topology checks ────────────────────────────────────────────────────
with entry {
    print("graph_populated", len(r.graph) > 0);
    print("type_map_populated", len(r.type_map) > 0);
    print("node_count", len(r.type_map));
}

# ── Direct TTG generation & structural verification ─────────────────────────
with entry {
    # TTG for HttpCrawler
    (ttg1, vis1, cm1) = JacTTGGenerator.get_ttg(
        HttpCrawler(), r.__jac__.id, r.graph, r.type_map
    );
    print("ttg1_total", count_ttg_nodes(ttg1));
    print("ttg1_visited", len(vis1));
    print("ttg1_types", sorted(collect_ttg_node_types(ttg1, r.type_map)));
    print("ttg1_max_depth", max_depth(ttg1));

    # TTG for ServiceDbCrawler
    (ttg2, vis2, cm2) = JacTTGGenerator.get_ttg(
        ServiceDbCrawler(), r.__jac__.id, r.graph, r.type_map
    );
    print("ttg2_total", count_ttg_nodes(ttg2));
    print("ttg2_visited", len(vis2));
    print("ttg2_types", sorted(collect_ttg_node_types(ttg2, r.type_map)));
    print("ttg2_max_depth", max_depth(ttg2));

    # TTG for FullCrawler
    (ttg3, vis3, cm3) = JacTTGGenerator.get_ttg(
        FullCrawler(), r.__jac__.id, r.graph, r.type_map
    );
    print("ttg3_total", count_ttg_nodes(ttg3));
    print("ttg3_visited", len(vis3));
    print("ttg3_types", sorted(collect_ttg_node_types(ttg3, r.type_map)));
    print("ttg3_max_depth", max_depth(ttg3));
}
