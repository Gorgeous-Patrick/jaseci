"""Persistent graph setup shared by the independent TTG test modules."""
import from pathlib { Path }
import from uuid { UUID }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.runtime.context { ExecutionContext }
import from .ttg_prefetch_walkers {
    FetchA,
    FetchB,
    FetchC,
    FetchSubC,
    FetchD,
    FetchStop,
    FetchLink,
    FetchOther,
    FetchSubLink,
    FetchNoise
}

def seed_fetch_graph(project: str, value: int = 13, multihop: bool = False) -> dict {
    ctx = ExecutionContext(
        base_path_dir=project, full_target_path=str(Path(project, 'fetch.jac'))
    );
    JacRuntime.exec_ctx = ctx;
    a = FetchA(value=value);
    b = FetchB();
    root ++> a;
    a +>:FetchLink:+> b;
    c0 = FetchC(label='c0');
    c1 = FetchC(label='c1');
    c2 = FetchSubC(label='c2');
    b +>:FetchLink:+> c0;
    b +>:FetchLink:+> c1;
    b +>:FetchSubLink:+> c2;
    cs = [c0, c1, c2];
    ds = [FetchD(label='d' + str(i)) for i in range(3)];
    for d in ds {
        d +>:FetchLink:+> b;
    }
    decoy = FetchC(label='wrong-edge');
    b +>:FetchOther:+> decoy;
    mids: list[FetchNoise] = [];
    if multihop {
        mids = [FetchNoise(), FetchNoise()];
        for mid in mids {
            b +>:FetchOther:+> mid;
        }
        mids[0] +>:FetchLink:+> c0;
        mids[0] +>:FetchLink:+> c1;
        mids[1] +>:FetchLink:+> c0;
        mids[1] +>:FetchSubLink:+> c2;
    }
    stop = FetchStop();
    a ++> stop;
    ctx.mem.commit();
    result = {
        'start': a.__jac__.id,
        'b': {b.__jac__.id},
        'stop': {stop.__jac__.id},
        'c': {n.__jac__.id for n in cs},
        'd': {n.__jac__.id for n in ds},
        'decoy': decoy.__jac__.id,
        'intermediate': {n.__jac__.id for n in mids}
    };
    ctx.close();
    return result;
}

def open_fetch_context(project: str) -> ExecutionContext {
    ctx = ExecutionContext(
        base_path_dir=project, full_target_path=str(Path(project, 'fetch.jac'))
    );
    JacRuntime.exec_ctx = ctx;
    return ctx;
}

def fetch_origin(ctx: ExecutionContext, uid: any) -> FetchA {
    assert isinstance(uid, UUID);
    anchor = ctx.mem.get(uid);
    assert anchor is not None;
    arch = anchor.archetype;
    assert isinstance(arch, FetchA);
    return arch;
}
