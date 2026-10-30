"""Uninstrumented source used to test automatic dependency hook placement."""
import from .ttg_dependency_walkers { DepStart, DepA, DepB, DepC, DepD }

walker HookRelevantQueue {
    has mode: int = 0;

    can start with DepStart entry {
        self.mode = here.value;
    }

    can intervening with DepA entry {
        self.mode = 0;
    }

    can target with DepB entry {
        if self.mode > 10 {
            visit [-->[?:DepC]];
        } else {
            visit [-->[?:DepD]];
        }
    }
}

walker HookCancelQueue {
    has mode: int = 0;

    can start with DepStart entry {
        self.mode = here.value;
    }

    can intervening with DepA entry {
        disengage;
    }

    can target with DepB entry {
        if self.mode > 10 {
            visit [-->[?:DepC]];
        }
    }
}
