"""Persistent fixtures for checkpoint-driven selective prefetch."""
node FetchA {
    has value: int = 13;
}

node FetchB {}
node FetchC {
    has label: str = '';
}

node FetchSubC(FetchC) {}
node FetchD {
    has label: str = '';
}

node FetchNoise {}
node FetchStop {}
edge FetchLink {}
edge FetchOther {}
edge FetchSubLink(FetchLink) {}

walker FetchBranch {
    has mode: int = 0,
        counter: int = 0,
        seen: list[str] = [];

    can start with FetchA entry {
        self.mode = here.value;
        visit [->:FetchLink:->[?:FetchB]];
        self.counter = self.counter + 1;
        if self.counter < 0 {
            visit [-->[?:FetchNoise]];
        }
    }

    can choose with FetchB entry {
        if self.mode > 10 {
            visit [->:FetchLink:->[?:FetchC]];
        } else {
            visit [<-:FetchLink:<-[?:FetchD]];
        }
    }

    can collect_c with FetchC entry {
        self.seen.append(here.label);
    }

    can collect_d with FetchD entry {
        self.seen.append(here.label);
    }
}

walker FetchCancelled {
    has mode: int = 0;

    can start with FetchA entry {
        self.mode = here.value;
        visit [-->[?:FetchStop]];
        visit [->:FetchLink:->[?:FetchB]];
    }

    can stop with FetchStop entry {
        disengage;
    }

    can choose with FetchB entry {
        if self.mode > 10 {
            visit [->:FetchLink:->[?:FetchC]];
        }
    }
}

walker FetchBoth {
    has seen: list[str] = [];

    can start with FetchA entry {
        visit [->:FetchLink:->[?:FetchB]];
    }

    can choose with FetchB entry {
        visit [->:FetchLink:->[?:FetchC]];
        visit [<-:FetchLink:<-[?:FetchD]];
    }

    can collect_c with FetchC entry {
        self.seen.append(here.label);
    }

    can collect_d with FetchD entry {
        self.seen.append(here.label);
    }
}
