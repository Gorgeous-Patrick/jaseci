"""TPC-H Benchmark for Jac — Entry Point.

Usage:
    jac run main.jac

This will load all TPC-H .tbl files from the sibling tpch/ directory
and build the full graph with nodes and edges.
"""

import os;

include loader;

with entry {
    # Resolve path to tpch/ data directory (sibling of this project)
    script_dir = os.path.dirname(os.path.abspath(__file__));
    data_dir = os.path.join(script_dir, "..", "tpch");

    if not os.path.isdir(data_dir) {
        print(f"Error: TPC-H data directory not found at {data_dir}");
        print("Please ensure the tpch/ folder with .tbl files is present.");
    } else {
        print(f"TPC-H data directory: {os.path.abspath(data_dir)}");
        print("Starting graph construction...\n");
        load_tpch_graph(data_dir);
    }
}
