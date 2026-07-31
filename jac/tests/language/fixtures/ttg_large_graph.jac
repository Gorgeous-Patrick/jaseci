"""TTG large-graph integration fixture."""

edge HttpEdge {}
edge DbEdge {}
edge CacheEdge {}

node Server {
    has name: str;
}

node Database {
    has name: str;
}

node Cache {
    has name: str;
}

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

with entry {
    root +>: HttpEdge :+> s1;
    s1 +>: HttpEdge :+> s2;
    s2 +>: HttpEdge :+> s3;
    s3 +>: HttpEdge :+> s4;
    s1 +>: DbEdge :+> d1;
    s2 +>: DbEdge :+> d2;
    s3 +>: DbEdge :+> d3;
    s4 +>: DbEdge :+> d4;
    d1 +>: DbEdge :+> d2;
    d2 +>: DbEdge :+> d3;
    d3 +>: DbEdge :+> d4;
    d1 +>: CacheEdge :+> c1;
    d2 +>: CacheEdge :+> c2;
    d3 +>: CacheEdge :+> c3;
    d4 +>: CacheEdge :+> c4;
    c1 +>: HttpEdge :+> s5;
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

with entry {
    w1 = HttpCrawler() spawn root;
    print("w1_visited", sorted(w1.visited));
    print("w1_ttg_visits", len(HttpCrawler.__jac_ttg_visits__));
}

with entry {
    w2 = ServiceDbCrawler() spawn root;
    print("w2_visited", sorted(w2.visited));
    print("w2_ttg_visits", len(ServiceDbCrawler.__jac_ttg_visits__));
}

with entry {
    w3 = FullCrawler() spawn root;
    print("w3_visited", sorted(w3.visited));
    print("w3_ttg_visits", len(FullCrawler.__jac_ttg_visits__));
}
