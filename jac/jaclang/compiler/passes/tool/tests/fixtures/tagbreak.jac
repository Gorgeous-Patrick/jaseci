#this file is part of formatter tests and is not meant to be run
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


class ModuleManager {
    def clear_alerts_for_file(self: ModuleManager, file_path_fs: str) -> None {
        #list comprehension example
        self.warnings_had = [w for w in self.program if w.loc.mod_path != file_path_fs];
        self.program.errors_had = [
            e for e in self.program.errors_haddddddddd if e.loc.mod_path != file_path_fs
        ];
        self.program.errors_had = [
            e
            for e in self.program.errors_haddddddddddddddddddddddddddddddddddddddddd if e.loc.mod_path != file_path_fs
        ];
        # dict comprehension example
        squares_dict = {x : x ** 2 for x in numbers};
        squares_dict = {
            x : x ** 2 for x in numberssssssssssssssssssssssssssssssssssssssssssssss
        };
        squares_dict = {
            x : x ** 2
            for x in numbersssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss
        };
        # set comprehension example
        squares_set = {x ** 2 for x in numbers};
        squares_set = {
            x ** 2 for x in numberssssssssssssssssssssssssssssssssssssssssssssssss
        };
        squares_set = {
            x ** 2
            for x in numbersssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss
        };
        # generator comprehension example
        squares_gen = (x ** 2 for x in numbers);
        squares_gen = (
            x ** 2 for x in numberssssssssssssssssssssssssssssssssssssssssssssssssssss
        );
        squares_gen = (
            x ** 2
            for x in numbersssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss
        );
    }
}
