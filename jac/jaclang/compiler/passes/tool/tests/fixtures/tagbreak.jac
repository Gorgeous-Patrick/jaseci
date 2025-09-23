class SemTokManager {
    """Initialize semantic token manager."""
    def init(self: SemTokManager, ir: uni.Module) -> None {
        self.aaaaastatic_sem_tokens:
            List[Tuple[lspt.Position, int, int, uni.AstSymbolNode]] = self.gen_sem_tok_node(
            ir
        );
    }
}


def walrus_example() {
    if ((x := 10) > 5) {
        print(x);
        b = a(
            11111111111111111111111111111111111111111111111111111111111111111111111111
        );
    }
}


with entry {
    c = (
        a()
        if 1 and isinstance(a, int)
        and isinstance(a, int)
        and isinstance(a, int)
        and isinstance(a, int)
        and isinstance(a, int)
        else (
            999
            if isinstance(a, int)
            and isinstance(a, int)
            and isinstance(a, int)
            and isinstance(4, bool)
            else 7
        )
    );
    print(
        """This is a long
        line of code."""
    );
}
