"""TTG basic integration fixture."""

edge BasicEdge {}
edge SpecialEdge {}

node TypeA {
    has val: int;
}

node TypeB {
    has val: int;
}

walker TTGWalker {
    has visited: list[int] = [];

    can enter_root with Root entry {
        visit [->:BasicEdge:->];
    }

    can run with TypeA entry {
        self.visited.append(here.val);
        visit [->:BasicEdge:->];
    }
}

glob a1 = TypeA(val=1),
     a2 = TypeA(val=2),
     b3 = TypeB(val=3),
     b4 = TypeB(val=4);

with entry {
    root +>: BasicEdge :+> a1;
    a1 +>: BasicEdge :+> a2;
    a2 +>: SpecialEdge :+> b3;
    a1 +>: BasicEdge :+> b4;
}

glob w = TTGWalker() spawn root;

with entry {
    print("visited", sorted(w.visited));
    print("ttg_visits", len(TTGWalker.__jac_ttg_visits__));
}
