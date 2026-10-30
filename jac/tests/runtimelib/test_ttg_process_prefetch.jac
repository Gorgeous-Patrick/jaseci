"""Real independent-process fetch, IPC preservation and child cleanup."""
import os;
import from tempfile { TemporaryDirectory }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.runtime.prefetch { dispatch_prefetch }
import from .fixtures.ttg_prefetch_helpers { seed_fetch_graph, open_fetch_context }

test "process prefetch uses distinct processes and transfers complete raw node payloads" {
    original = JacRuntime.exec_ctx;
    try {
        with TemporaryDirectory() as project {
            ids = seed_fetch_graph(project);
            ctx = open_fetch_context(project);
            mem: any = ctx.mem;
            children: list[int] = [];
            failures: list[str] = [];
            def completed(batch: list, elapsed: float, error: str | None) {
                if error is not None {
                    failures.append(error);
                }
            }
            try {
                dispatch_prefetch(
                    ctx, list(ids['c']), 'process', 2, observer=completed
                );
                for thread in getattr(mem, '_prefetch_threads', []) {
                    thread.join();
                }
                assert not failures , str(failures);
                children = list(getattr(mem, '_prefetch_process_pids', []));
                assert len(set(children)) == 2;
                assert os.getpid() not in children;
                with ctx.mem._raw_lock {
                    assert ids['c'] <= set(ctx.mem.__raw_mem__) , str(
                        ctx.mem.__raw_mem__
                    );
                }
                labels: set[str] = set();
                for uid in ids['c'] {
                    anchor = ctx.mem.get(uid);
                    assert anchor is not None;
                    assert anchor.id == uid;
                    arch: any = anchor.archetype;
                    labels.add(arch.label);
                }
                assert labels == {'c0', 'c1', 'c2'};
            } finally {
                ctx.close();
            }
            for pid in children {
                running = True;
                try {
                    os.kill(pid, 0);
                } except ProcessLookupError {
                    running = False;
                }
                assert not running , 'Child process survived Session.close: '
                    + str(pid);
            }
        }
    } finally {
        JacRuntime.exec_ctx = original;
    }
}
