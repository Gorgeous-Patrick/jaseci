"""TPC-H Benchmark for Jac — Entry Point.

Usage:
    jac run main.jac

This will load all TPC-H .tbl files from the sibling tpch/ directory,
build the full graph, and demonstrate running query walkers.

Graph hierarchy:
    root -> Region -> Nation -> Supplier -> PartSupp
                             -> Customer -> Order -> LineItem -> PartSupp
    root -> Part -> PartSupp

Walkers Q1–Q22 implement the 22 TPC-H queries.
All spawn on root and report results.
"""

import os;

include loader;
include queries;

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
        print("\nGraph loaded. You can now spawn walkers, e.g.:");
        print("  result = root spawn Q1_PricingSummary();");
        print("  result = root spawn Q6_ForecastingRevenue();");
    }
}
