"""TPC-H Benchmark: Data loader.

Reads pipe-delimited .tbl files from the tpch/ directory and constructs
the full TPC-H graph. Only Region and Part nodes connect directly to root.
All other nodes are reachable indirectly through typed FK edges.

Graph hierarchy:
    root -> Region -> Nation -> Supplier -> PartSupp
                             -> Customer -> Order -> LineItem -> PartSupp
    root -> Part -> PartSupp
"""

import os;
import time;

include models;

"""Build the full path to a .tbl file inside the data directory."""
def tbl_path(data_dir: str, filename: str) -> str {
    return os.path.join(data_dir, filename);
}

"""Read a pipe-delimited .tbl file and return a list of field-lists.

TPC-H .tbl files use '|' as delimiter with a trailing '|' on each line.
"""
def read_tbl(filepath: str) -> list {
    rows: list = [];
    with open(filepath, "r") as f {
        for line in f {
            line = line.strip();
            if line {
                # Strip trailing pipe then split
                if line.endswith("|") {
                    line = line[:-1];
                }
                rows.append(line.split("|"));
            }
        }
    }
    return rows;
}

"""Load the full TPC-H dataset into the graph rooted at `root`.

Args:
    data_dir: Path to the directory containing .tbl files.

Only Region and Part connect directly to root.
All other nodes are connected through their foreign-key edges,
forming a hierarchy that walkers can traverse from root.
"""
def load_tpch_graph(data_dir: str) -> None {
    total_start = time.time();

    # ── Lookup tables (primary key -> node reference) ──
    region_map: dict = {};
    nation_map: dict = {};
    part_map: dict = {};
    supplier_map: dict = {};
    customer_map: dict = {};
    order_map: dict = {};
    # PartSupp has composite key (partkey, suppkey)
    partsupp_map: dict = {};

    # ────────────────────────────────────────────
    #  1. Load REGION (5 rows) — connected to root
    # ────────────────────────────────────────────
    t0 = time.time();
    print("[1/8] Loading regions...", flush=True);
    for row in read_tbl(tbl_path(data_dir, "region.tbl")) {
        n = root ++> Region(
            r_regionkey=int(row[0]),
            r_name=row[1].strip(),
            r_comment=row[2].strip()
        );
        region_map[int(row[0])] = n[0];
    }
    print(f"  ✓ {len(region_map)} regions ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  2. Load NATION (25 rows, FK: N_REGIONKEY -> REGION)
    #     Connected via: Region -[region_has_nation]-> Nation
    # ────────────────────────────────────────────
    t0 = time.time();
    print("[2/8] Loading nations...", flush=True);
    for row in read_tbl(tbl_path(data_dir, "nation.tbl")) {
        regionkey = int(row[2]);
        nation_node = Nation(
            n_nationkey=int(row[0]),
            n_name=row[1].strip(),
            n_comment=row[3].strip()
        );
        # Connect via Region -> Nation edge
        if regionkey in region_map {
            n = region_map[regionkey] +>: region_has_nation() :+> nation_node;
            nation_map[int(row[0])] = n[0];
        }
    }
    print(f"  ✓ {len(nation_map)} nations ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  3. Load PART (20,000 rows) — connected to root
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "part.tbl"));
    total = len(rows);
    print(f"[3/8] Loading parts (0/{total})...", flush=True);
    count = 0;
    for row in rows {
        n = root ++> Part(
            p_partkey=int(row[0]),
            p_name=row[1].strip(),
            p_mfgr=row[2].strip(),
            p_brand=row[3].strip(),
            p_type=row[4].strip(),
            p_size=int(row[5]),
            p_container=row[6].strip(),
            p_retailprice=float(row[7]),
            p_comment=row[8].strip()
        );
        part_map[int(row[0])] = n[0];
        count += 1;
        if count % 10000 == 0 {
            elapsed = time.time() - t0;
            rate = count / elapsed if elapsed > 0 else 0;
            print(f"  ... {count}/{total} ({rate:.0f} rows/s)", flush=True);
        }
    }
    print(f"  ✓ {len(part_map)} parts ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  4. Load SUPPLIER (1,000 rows, FK: S_NATIONKEY -> NATION)
    #     Connected via: Nation -[nation_has_supplier]-> Supplier
    # ────────────────────────────────────────────
    t0 = time.time();
    print("[4/8] Loading suppliers...", flush=True);
    for row in read_tbl(tbl_path(data_dir, "supplier.tbl")) {
        nationkey = int(row[3]);
        supplier_node = Supplier(
            s_suppkey=int(row[0]),
            s_name=row[1].strip(),
            s_address=row[2].strip(),
            s_phone=row[4].strip(),
            s_acctbal=float(row[5]),
            s_comment=row[6].strip()
        );
        # Connect via Nation -> Supplier edge
        if nationkey in nation_map {
            n = nation_map[nationkey] +>: nation_has_supplier() :+> supplier_node;
            supplier_map[int(row[0])] = n[0];
        }
    }
    print(f"  ✓ {len(supplier_map)} suppliers ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  5. Load CUSTOMER (15,000 rows, FK: C_NATIONKEY -> NATION)
    #     Connected via: Nation -[nation_has_customer]-> Customer
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "customer.tbl"));
    total = len(rows);
    print(f"[5/8] Loading customers (0/{total})...", flush=True);
    count = 0;
    for row in rows {
        nationkey = int(row[3]);
        customer_node = Customer(
            c_custkey=int(row[0]),
            c_name=row[1].strip(),
            c_address=row[2].strip(),
            c_phone=row[4].strip(),
            c_acctbal=float(row[5]),
            c_mktsegment=row[6].strip(),
            c_comment=row[7].strip()
        );
        # Connect via Nation -> Customer edge
        if nationkey in nation_map {
            n = nation_map[nationkey] +>: nation_has_customer() :+> customer_node;
            customer_map[int(row[0])] = n[0];
        }
        count += 1;
        if count % 10000 == 0 {
            elapsed = time.time() - t0;
            rate = count / elapsed if elapsed > 0 else 0;
            print(f"  ... {count}/{total} ({rate:.0f} rows/s)", flush=True);
        }
    }
    print(f"  ✓ {len(customer_map)} customers ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  6. Load PARTSUPP (80,000 rows, FK: PS_PARTKEY -> PART, PS_SUPPKEY -> SUPPLIER)
    #     Connected via: Part -[part_supplied_by]-> PartSupp
    #                    Supplier -[supplier_supplies]-> PartSupp
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "partsupp.tbl"));
    total = len(rows);
    print(f"[6/8] Loading partsupp (0/{total})...", flush=True);
    ps_count = 0;
    for row in rows {
        partkey = int(row[0]);
        suppkey = int(row[1]);
        partsupp_node = PartSupp(
            ps_partkey=partkey,
            ps_suppkey=suppkey,
            ps_availqty=int(row[2]),
            ps_supplycost=float(row[3]),
            ps_comment=row[4].strip()
        );
        composite_key = f"{partkey}_{suppkey}";
        ps_count += 1;
        # Primary connection: Part -> PartSupp
        if partkey in part_map {
            n = part_map[partkey] +>: part_supplied_by() :+> partsupp_node;
            partsupp_map[composite_key] = n[0];
            # Also connect Supplier -> PartSupp
            if suppkey in supplier_map {
                supplier_map[suppkey] +>: supplier_supplies() :+> n[0];
            }
        } elif suppkey in supplier_map {
            # Fallback: connect via Supplier if Part not found
            n = supplier_map[suppkey] +>: supplier_supplies() :+> partsupp_node;
            partsupp_map[composite_key] = n[0];
        }
        if ps_count % 10000 == 0 {
            elapsed = time.time() - t0;
            rate = ps_count / elapsed if elapsed > 0 else 0;
            eta = (total - ps_count) / rate if rate > 0 else 0;
            print(f"  ... {ps_count}/{total} ({rate:.0f} rows/s, ETA {eta:.0f}s)", flush=True);
        }
    }
    print(f"  ✓ {ps_count} partsupp records ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  7. Load ORDERS (150,000 rows, FK: O_CUSTKEY -> CUSTOMER)
    #     Connected via: Customer -[customer_ordered]-> Order
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "orders.tbl"));
    total = len(rows);
    print(f"[7/8] Loading orders (0/{total})...", flush=True);
    count = 0;
    for row in rows {
        custkey = int(row[1]);
        order_node = Order(
            o_orderkey=int(row[0]),
            o_custkey=int(row[1]),
            o_orderstatus=row[2].strip(),
            o_totalprice=float(row[3]),
            o_orderdate=row[4].strip(),
            o_orderpriority=row[5].strip(),
            o_clerk=row[6].strip(),
            o_shippriority=int(row[7]),
            o_comment=row[8].strip()
        );
        # Connect via Customer -> Order edge
        if custkey in customer_map {
            n = customer_map[custkey] +>: customer_ordered() :+> order_node;
            order_map[int(row[0])] = n[0];
        }
        count += 1;
        if count % 10000 == 0 {
            elapsed = time.time() - t0;
            rate = count / elapsed if elapsed > 0 else 0;
            eta = (total - count) / rate if rate > 0 else 0;
            print(f"  ... {count}/{total} ({rate:.0f} rows/s, ETA {eta:.0f}s)", flush=True);
        }
    }
    print(f"  ✓ {len(order_map)} orders ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  8. Load LINEITEM (600,572 rows, FK: L_ORDERKEY -> ORDERS,
    #                     L_PARTKEY+L_SUPPKEY -> PARTSUPP)
    #     Connected via: Order -[order_has_lineitem]-> LineItem
    #                    LineItem -[lineitem_partsupp]-> PartSupp
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "lineitem.tbl"));
    total = len(rows);
    print(f"[8/8] Loading lineitems (0/{total})...", flush=True);
    li_count = 0;
    for row in rows {
        orderkey = int(row[0]);
        partkey = int(row[1]);
        suppkey = int(row[2]);
        lineitem_node = LineItem(
            l_orderkey=orderkey,
            l_partkey=partkey,
            l_suppkey=suppkey,
            l_linenumber=int(row[3]),
            l_quantity=float(row[4]),
            l_extendedprice=float(row[5]),
            l_discount=float(row[6]),
            l_tax=float(row[7]),
            l_returnflag=row[8].strip(),
            l_linestatus=row[9].strip(),
            l_shipdate=row[10].strip(),
            l_commitdate=row[11].strip(),
            l_receiptdate=row[12].strip(),
            l_shipinstruct=row[13].strip(),
            l_shipmode=row[14].strip(),
            l_comment=row[15].strip()
        );
        li_count += 1;
        # Primary connection: Order -> LineItem
        if orderkey in order_map {
            n = order_map[orderkey] +>: order_has_lineitem() :+> lineitem_node;
            # Secondary: LineItem -> PartSupp
            composite_key = f"{partkey}_{suppkey}";
            if composite_key in partsupp_map {
                n[0] +>: lineitem_partsupp() :+> partsupp_map[composite_key];
            }
        }
        if li_count % 10000 == 0 {
            elapsed = time.time() - t0;
            rate = li_count / elapsed if elapsed > 0 else 0;
            eta = (total - li_count) / rate if rate > 0 else 0;
            print(f"  ... {li_count}/{total} ({rate:.0f} rows/s, ETA {eta:.0f}s)", flush=True);
        }
    }
    print(f"  ✓ {li_count} lineitems ({time.time() - t0:.1f}s)", flush=True);

    total_elapsed = time.time() - total_start;
    total_nodes = len(region_map) + len(nation_map) + len(part_map) + len(supplier_map) + len(customer_map) + ps_count + len(order_map) + li_count;
    print(f"\n{'='*50}", flush=True);
    print(f"TPC-H graph construction complete!", flush=True);
    print(f"  Total nodes: {total_nodes:,}", flush=True);
    print(f"  Total time:  {total_elapsed:.1f}s ({total_nodes / total_elapsed:.0f} nodes/s)", flush=True);
    print(f"{'='*50}", flush=True);
}
