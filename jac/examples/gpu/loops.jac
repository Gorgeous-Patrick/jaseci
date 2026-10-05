"""Dynamic device loops; build with --gpu-entry LoopSum (chain or CSR)."""
node LoopCell { has value: int; }
edge LoopNext {}
walker LoopSum {
    has total: int = 0;
    can step with LoopCell entry {
        remaining = here.value;
        for i in range(here.value) {
            for j in range(2) { self.total += i + j; }
        }
        while remaining > 0 {
            self.total += remaining;
            remaining -= 1;
        }
        visit [->:LoopNext:->];
    }
}
with entry {
    a = LoopCell(value=3);
    b = LoopCell(value=2);
    a +>:LoopNext():+> b;
    w = LoopSum();
    a spawn w;
    print(w.total); # 22 on CPU and GPU
}
