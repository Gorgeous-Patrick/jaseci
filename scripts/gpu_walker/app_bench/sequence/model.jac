"""Weighted transaction-event chains for the experimental Jac GPU runtime."""

node Event {
    has amount: int,
        weight: int,
        adjustment: int,
        active: int;
}

edge Next {}

walker RiskScore {
    has score: int = 0,
        visited: int = 0;

    can inspect with Event entry {
        self.visited += 1;
        if here.active == 1 {
            self.score += here.amount * here.weight + here.adjustment;
        }
        visit [->:Next:->];
    }
}

def amount_for(lane: int, hop: int) -> int {
    return (lane * 7 + hop * 3) % 17 - 8;
}

def weight_for(lane: int, hop: int) -> int {
    return (lane + hop) % 5 + 1;
}

def adjustment_for(lane: int, hop: int) -> int {
    return (lane * 3 + hop) % 7 - 3;
}

def active_for(lane: int, hop: int) -> int {
    return 0 if (lane + hop) % 4 == 0 else 1;
}

def initial_score(lane: int) -> int {
    return lane % 11 - 5;
}

def make_workload(batch: int, length: int) -> tuple[list[Event], list[Event]] {
    if batch <= 0 or length <= 0 {
        raise ValueError("Batch and chain length must be positive");
    }
    starts: list[Event] = [];
    nodes: list[Event] = [];
    for lane in range(batch) {
        previous: any = None;
        for hop in range(length) {
            current = Event(
                amount=amount_for(lane, hop),
                weight=weight_for(lane, hop),
                adjustment=adjustment_for(lane, hop),
                active=active_for(lane, hop)
            );
            nodes.append(current);
            if previous is None {
                starts.append(current);
            } else {
                previous +>:Next():+> current;
            }
            previous = current;
        }
    }
    return starts, nodes;
}

def expected_scores(nodes: list[Event], batch: int, length: int) -> list[int] {
    if len(nodes) != batch * length {
        raise ValueError("Incomplete event graph");
    }
    scores: list[int] = [];
    for lane in range(batch) {
        total = initial_score(lane);
        for hop in range(length) {
            event = nodes[lane * length + hop];
            if event.active == 1 {
                total += (
                    event.amount * event.weight + event.adjustment
                );
            }
        }
        scores.append(total);
    }
    return scores;
}
