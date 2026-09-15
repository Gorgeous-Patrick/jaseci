"""The portable scheduler owns order even when its adapter predicts ahead."""

import from jaclang.runtime.osp_kernel {
    OspEngine,
    OspRuntime,
    OspTask,
    Slot,
    WalkerDesc,
    NodeDesc,
    WalkScope,
    osp_visit,
    osp_skip_rest,
    osp_disengage,
    osp_spawn
}

glob trace: list[str] = [],
     batches: list[list[int]] = [],
     dropped: list[int] = [],
     settings: dict[str, any] = {"reject": -1, "control": ""};

def entry_step(w: any, n: int) {
    trace.append("E" + str(n));
    if n == 1 {
        osp_visit([2, 3]);
    } elif n == 2 {
        osp_visit([4]);
    }
    if n == 2 and settings["control"] == "skip" {
        osp_skip_rest();
    }
    if n == 2 and settings["control"] == "stop" {
        osp_disengage();
    }
}

def second_step(w: any, n: int) {
    trace.append("S" + str(n));
}

def exit_step(w: any, n: int) {
    trace.append("X" + str(n));
    if n == 3 and settings["control"] == "exit_visit" {
        osp_visit([5]);
    }
}

def run_tasks(tasks: list[OspTask]) {
    batches.append([int(t.b) for t in tasks]);
    for t in tasks {
        t.state = 1;
    }
}

def commit_task(task: OspTask) -> bool {
    if task.b == settings["reject"] {
        return False;
    }
    task.slot.fn(task.a, task.b);
    return True;
}

def drop_task(task: OspTask) {
    assert task.state == 1;
    task.state = 0;
    dropped.append(int(task.b));
}

def tag_of(n: any) -> int {
    return 1;
}

def is_a(a: int, b: int) -> bool {
    return a == b;
}

def node_desc(tag: int) -> NodeDesc {
    return NodeDesc(tag, [], []);
}

def on_complete(scope: WalkScope, ok: bool) {}

def run_case(width: int) -> list[str] {
    trace.clear();
    batches.clear();
    dropped.clear();
    rt = OspRuntime(
        tag_of=tag_of,
        is_a=is_a,
        node_desc=node_desc,
        on_complete=on_complete,
        task_width=width,
        run_tasks=run_tasks,
        commit_task=commit_task,
        drop_task=drop_task
    );
    wd = WalkerDesc(
        10, [Slot(1, entry_step), Slot(1, second_step)], [Slot(1, exit_step)]
    );
    osp_spawn(rt, 99, wd, [1]);
    assert sum(len(batch) for batch in batches) == len(dropped);
    return list(trace);
}

test "preview retains FIFO entries and reverse exits across batches" {
    expected = run_case(0);
    assert expected
        == ["E1", "S1", "E2", "S2", "E3", "S3", "E4", "S4", "X4", "X3", "X2", "X1"];
    assert run_case(4) == expected;
    assert any(2 in batch and 3 in batch for batch in batches);
}

test "rejected predictions and traversal controls preserve serial order" {
    for mode in ("", "skip", "stop", "exit_visit") {
        settings["control"] = mode;
        expected = run_case(0);
        for rejected in (-1, 2, 3) {
            settings["reject"] = rejected;
            assert run_case(4) == expected;
        }
    }
    settings["reject"] = -1;
    settings["control"] = "";
}

test "preview does not consume a live queue or mutate live frames" {
    engine = OspEngine([]);
    scope = engine.begin(99, [1, 1, 2]);
    copy = engine.preview(scope);
    copy.next.pop();
    copy.path.append(1);
    assert scope.next == [1, 1, 2];
    assert scope.path == [];
    assert scope.frames == [];
}
