obj Position {
    has x: int,
        y: int;
}

node Sample {
    has value: int,
        weight: int,
        position: Position;
}

edge Link {}

walker WeightedSum {
    has total: int = 0;

    can step with Sample entry {
        if here.position.x >= 0 {
            self.total += here.value * here.weight + here.position.y;
        } else {
            self.total += here.position.x;
        }
        visit [->:Link:->];
    }
}
