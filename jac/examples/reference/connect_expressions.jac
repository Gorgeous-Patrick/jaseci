# Connect expressions - Graph edge creation and connection operators

node node_a {
    has value: int;
}

walker Creator {
    can create with `root entry;
    can travel with `root | node_a entry;
}

edge MyEdge {
    has val: int = 5;
}

impl Creator.create {
    end = here;
    for i=0 to i<7 by i+=1  {
        if i % 2 == 0 {
            # Simple connect operator (++>)
            end ++> (end := node_a(value=i));
        } else {
            # Typed connect with edge type and attributes (+>:Type:attr=val:+>)
            end +>:MyEdge:val=i:+> (end := node_a(value=i + 10));
        }
    }
}

impl Creator.travel {
    # Edge traversal with filter
    for i in [->:MyEdge:val <= 6:->] {
        print(i.value);
    }
    visit [-->];
}

with entry :__main__ {
    root spawn Creator();
}
