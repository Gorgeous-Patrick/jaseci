"""Finite typed regions independent of benchmark names or counter cutoffs."""
node RegionItem {
    has value: int = 0;
}

edge RegionNext {}
walker RegionTraverse {
    can walk with RegionItem entry {
        report here.value;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

walker RegionReduction {
    has total: int = 0;

    can walk with RegionItem entry {
        self.total += here.value;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

node RegionA {}
node RegionB {
    has active: bool = True;
}

node RegionC {
    has value: int = 9;
}

edge RegionAB {}
edge RegionBC {}
walker RegionGuard {
    can start with RegionA entry {
        visit [->:RegionAB:->[?:RegionB]];
    }

    can middle with RegionB entry {
        if here.active {
            visit [->:RegionBC:->[?:RegionC]];
        }
    }

    can finish with RegionC entry {
        report here.value;
    }
}

walker RegionShared {
    has count: int = 0;

    can walk with RegionItem entry {
        self.count += 1;
        if self.count < 4 {
            visit [->:RegionNext:->[?:RegionItem]];
        }
    }
}

walker RegionCancel {
    can walk with RegionItem entry {
        disengage;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

walker RegionWrite {
    can walk with RegionItem entry {
        here.value = 7;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

walker RegionUnknown {
    can walk with RegionItem entry {
        self.opaque();
        visit [->:RegionNext:->[?:RegionItem]];
    }

    def opaque {
        return;
    }
}

walker RegionCounterOutput {
    has visited: int = 0;

    can walk with RegionItem entry {
        self.visited += 1;
        report here.value;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

walker RegionDivision {
    has total: int = 1;

    can walk with RegionItem entry {
        self.total //= here.value;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

walker RegionAssign {
    has sink: int = 0;

    can walk with RegionItem entry {
        self.sink = 1;
        visit [->:RegionNext:->[?:RegionItem]];
    }
}

node RegionFrontRoot {}
node RegionFrontHub {}
edge RegionFrontEdge {}
edge RegionFrontLeft {}
edge RegionFrontRight {}
walker RegionFrontier {
    can start with RegionFrontRoot entry {
        visit [-->[?:RegionFrontHub]];
    }

    can collect with RegionFrontHub entry {
        visit [->:RegionFrontLeft:->[?:RegionC]];
        visit [->:RegionFrontRight:->[?:RegionC]];
    }

    can gather with RegionC entry {
        report here.value;
    }
}

node DagProfile {}
node DagTweet {
    has value: int = 0;
}

node DagCustomTweet(DagTweet) {
    def __jac_access__ -> any {
        raise AssertionError('Access hook must not run during certification');
    }
}

edge DagPost {}
edge DagFollow {}
walker DagFeed {
    has feed: list[int] = [];

    can run with Root entry {
        visit [-->[?:DagProfile]];
    }

    can collect with DagProfile entry {
        visit [->:DagPost:->[?:DagTweet]];
        visit [->:DagFollow:->[?:DagProfile]->:DagPost:->[?:DagTweet]];
    }

    can gather with DagTweet entry {
        self.feed.append(here.value);
    }

    can deliver with Root exit {
        report self.feed;
    }
}

walker DagShared {
    has seen: int = 0;

    can run with Root entry {
        visit [-->[?:DagProfile]];
    }

    can collect with DagProfile entry {
        self.seen += 1;
        if self.seen < 2 {
            visit [->:DagPost:->[?:DagTweet]];
        }
    }
}
