"""Small walkers whose paths depend on state computed before visit dispatch."""
node DepA {
    has value: int = 0;
}

node DepB {
    has enabled: bool = True;
}

node DepC {}
node DepD {}

walker DepWalker {
    has mode: int = 0;

    can on_a with DepA entry {
        x = here.value * 2;
        self.mode = x + 1;
        if self.mode > 0 {
            visit [-->[?:DepB]];
        }
    }

    can on_b with DepB entry {
        if self.mode > 10 {
            visit [-->[?:DepC]];
        } else {
            visit [-->[?:DepD]];
        }
    }
}

walker DepNeedsB {
    has mode: int = 0;

    can on_a with DepA entry {
        self.mode = here.value;
        visit [-->[?:DepB]];
    }

    can on_b with DepB entry {
        if here.enabled {
            visit [-->[?:DepC]];
        }
    }
}

walker DepMutation {
    has mode: int = 0;

    can on_a with DepA entry {
        self.mode = here.value;
        visit [-->[?:DepB]];
        self.mode = 0;
    }

    can on_b with DepB entry {
        if self.mode > 0 {
            visit [-->[?:DepC]];
        }
    }
}

walker DepMerge {
    has mode: int = 0;

    can on_a with DepA entry {
        self.mode = here.value;
        if self.mode > 0 {
            self.mode = 12;
        } else {
            self.mode = 2;
        }
        visit [-->[?:DepB]];
    }

    can on_b with DepB entry {
        if self.mode > 10 {
            visit [-->[?:DepC]];
        } else {
            visit [-->[?:DepD]];
        }
    }
}

walker DepOverwrite {
    has mode: int = 0;

    can on_a with DepA entry {
        self.mode = here.value;
        visit [-->[?:DepB]];
    }

    can on_b with DepB entry {
        self.mode = 0;
        if self.mode > 0 {
            visit [-->[?:DepC]];
        }
    }
}

walker DepLoop {
    has mode: int = 0;

    can on_a with DepA entry {
        self.mode = here.value;
        while self.mode > 0 {
            self.mode -= 1;
        }
        visit [-->[?:DepB]];
    }
}

walker DepMultipleHandlers {
    has mode: int = 0;

    can on_a with DepA entry {
        self.mode = here.value;
        visit [-->[?:DepB]];
    }

    can first with DepB entry {
        if self.mode > 0 {
            visit [-->[?:DepC]];
        }
    }

    can second with DepB entry {
        self.mode = 0;
    }
}

node DepStart {
    has value: int = 13;
}

node DepNoise {}
node DepHook {
    can observe with entry {
        report 1;
    }
}

walker DepQueueWalker {
    has mode: int = 0,
        counter: int = 0;

    can on_start with DepStart entry {
        self.mode = here.value;
        self.counter = self.counter + 1;
    }

    can on_a with DepA entry {
        self.counter = self.counter + 1;
        if self.counter < 0 {
            visit [-->[?:DepD]];
        }
    }

    can on_a_exit with DepA exit {
        self.mode = 0;
    }

    can on_b with DepB entry {
        if self.mode > 10 {
            visit [-->[?:DepC]];
        } else {
            visit [-->[?:DepD]];
        }
    }
}

walker DepQueueCancels {
    has mode: int = 13;

    can on_a with DepA entry {
        disengage;
    }

    can on_b with DepB entry {
        if self.mode > 10 {
            visit [-->[?:DepC]];
        }
    }
}
