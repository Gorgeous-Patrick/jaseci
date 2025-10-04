# Disengage statements - Stop walker traversal

walker Visitor {
    can travel with `root entry {
        visit [-->] else {
            visit root;
        }
    }
}

node item {
    can speak with Visitor entry {
        print("Hey There!!!");
        # Disengage - stops walker execution and returns to caller
        disengage;
    }
}

with entry {
    # Build graph
    for i=0 to i<5 by i+=1  {
        root ++> item();
    }
    # Spawn walker - will disengage when it hits first node
    root spawn Visitor();
}
