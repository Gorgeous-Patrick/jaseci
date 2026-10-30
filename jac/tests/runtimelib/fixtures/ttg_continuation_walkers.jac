"""FIFO continuations used by the TTG planner regression tests."""
node ContinueA {}
node ContinueB {
    has value: int = 1;
}

node ContinueC {}
node ContinueD {}

walker ContinueChain {
    has count: int = 0;

    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
    }

    can second with ContinueB entry {
        self.count = self.count + 1;
        if self.count == 1 {
            visit [-->[?:ContinueC]];
        } else {
            visit [-->[?:ContinueD]];
        }
    }

    can third with ContinueC entry {
        visit [-->[?:ContinueD]];
    }

    can last with ContinueD entry { }
}

walker ContinueUnknown {
    has count: int = 0;

    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
    }

    can second with ContinueB entry {
        self.count = here.value;
        if self.count > 0 {
            visit [-->[?:ContinueC]];
        }
    }

    can third with ContinueC entry {
        visit [-->[?:ContinueD]];
    }

    can last with ContinueD entry { }
}

walker ContinueCancel {
    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
    }

    can second with ContinueB entry {
        disengage;
    }

    can third with ContinueC entry {
        visit [-->[?:ContinueD]];
    }
}

walker ContinueCycle {
    has count: int = 0;

    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
    }

    can second with ContinueB entry {
        self.count = self.count + 1;
        if self.count < 3 {
            visit [-->[?:ContinueB]];
        }
    }
}

walker ContinueAppend {
    has seen: list[int] = [];

    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
    }

    can second with ContinueB entry {
        self.seen.append(here.value);
        visit [-->[?:ContinueC]];
    }

    can third with ContinueC entry { }
}

walker ContinueSourceCancel {
    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
        disengage;
    }

    can second with ContinueB entry { }
}

walker ContinueExit {
    can first with ContinueA entry {
        visit [-->[?:ContinueB]];
    }

    can second with ContinueB entry { }
    can leave with ContinueA exit {
        visit [-->[?:ContinueC]];
    }
}
