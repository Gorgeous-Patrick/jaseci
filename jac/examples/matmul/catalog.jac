"""Registry of implemented CPU algorithms and OSP representations."""

import dense;
import recursive;
import sparse;
import graphs;
import libraries;

obj Implementation {
    has name: str,
        family: str,
        function: any;
}

def implementations(include_libraries: bool = True) -> list[Implementation] {
    result = [
        Implementation("loop_ijk", "dense", dense.loop_ijk),
        Implementation("loop_ikj", "dense", dense.loop_ikj),
        Implementation("loop_jik", "dense", dense.loop_jik),
        Implementation("loop_jki", "dense", dense.loop_jki),
        Implementation("loop_kij", "dense", dense.loop_kij),
        Implementation("loop_kji", "dense", dense.loop_kji),
        Implementation("transposed_dot", "dense", dense.transposed_dot),
        Implementation("comprehension", "dense", dense.comprehension),
        Implementation("flat_buffers", "dense", dense.flat_buffers),
        Implementation("blocked", "dense", dense.blocked),
        Implementation("packed_tiles", "dense", dense.packed_tiles),
        Implementation("register_2x2", "dense", dense.register_2x2),
        Implementation("split_k", "dense", dense.split_k),
        Implementation("pairwise", "reduction", dense.pairwise),
        Implementation("compensated", "reduction", dense.compensated),
        Implementation("accurate_sum", "reduction", dense.accurate_sum),
        Implementation("winograd_pairs", "dense", dense.winograd_pairs),
        Implementation("threaded_rows", "parallel", dense.threaded_rows),
        Implementation("overloaded_operator", "operator", dense.overloaded_operator),
        Implementation("recursive_blocks", "recursive", recursive.recursive_blocks),
        Implementation("strassen", "recursive", recursive.strassen),
        Implementation("strassen_winograd", "recursive", recursive.strassen_winograd),
        Implementation("csr_dense", "sparse", sparse.csr_dense),
        Implementation("csr_csc_merge", "sparse", sparse.csr_csc_merge),
        Implementation("coo_scatter", "sparse", sparse.coo_scatter),
        Implementation("product_chains", "OSP", graphs.product_chains),
        Implementation("dual_cursors", "OSP", graphs.dual_cursors),
        Implementation("row_nodes", "OSP", graphs.row_nodes),
        Implementation("output_cell_tasks", "OSP", graphs.output_cell_tasks),
        Implementation("output_tile_tasks", "OSP", graphs.output_tile_tasks),
        Implementation("bipartite_join", "OSP", graphs.bipartite_join),
        Implementation("edge_payloads", "OSP", graphs.edge_payloads)
    ];
    available = libraries.availability();
    if include_libraries and available["numpy"] {
        result += [
            Implementation("numpy_operator", "library", libraries.numpy_operator),
            Implementation("numpy_matmul", "library", libraries.numpy_matmul),
            Implementation("numpy_dot", "library", libraries.numpy_dot),
            Implementation("numpy_einsum", "library", libraries.numpy_einsum),
            Implementation("numpy_tensordot", "library", libraries.numpy_tensordot),
            Implementation("numpy_broadcast", "library", libraries.numpy_broadcast)
        ];
        if available["scipy"] {
            result += [
                Implementation("scipy_blas", "library", libraries.scipy_blas),
                Implementation("scipy_sparse", "library", libraries.scipy_sparse)
            ];
        }
    }
    return result;
}
