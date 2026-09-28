"""Source-checkout environment for the PTX differential verification script."""

import os
from pathlib import Path
import sys


def bootstrap(repo: Path, shim: Path, cache: Path):
    if not shim.is_file():
        raise FileNotFoundError(f"LLVM shim not found: {shim}")
    os.environ.update(
        JAC_NO_DEV_SOURCE="1", JAC_NO_PRECOMPILE="1",
        XDG_CACHE_HOME=str(cache.resolve()), JAC_LLVM_SHIM=str(shim.resolve()),
    )
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(repo.resolve() / "jac"))
    import _jac_finder

    _jac_finder.install()
    from jaclang.compiler.backends.native.llvm import binding as llvm, ir

    llvm.initialize_all_targets()
    llvm.initialize_all_asmprinters()
    return ir, llvm
