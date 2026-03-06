"""TPC-H Benchmark: Data loader.

Reads pipe-delimited .tbl files from the tpch/ directory and constructs
the full TPC-H graph — nodes for every row and edges for every foreign
key relationship.
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

The loader builds lookup dicts keyed by primary key so that edges
(foreign key relationships) can be wired up efficiently.
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
    #  1. Load REGION (5 rows)
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
    # ────────────────────────────────────────────
    t0 = time.time();
    print("[2/8] Loading nations...", flush=True);
    for row in read_tbl(tbl_path(data_dir, "nation.tbl")) {
        n = root ++> Nation(
            n_nationkey=int(row[0]),
            n_name=row[1].strip(),
            n_comment=row[3].strip()
        );
        nation_map[int(row[0])] = n[0];
        # Edge: Region -> Nation
        regionkey = int(row[2]);
        if regionkey in region_map {
            region_map[regionkey] +>: region_has_nation() :+> n[0];
        }
    }
    print(f"  ✓ {len(nation_map)} nations ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  3. Load PART (20,000 rows)
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
    # ────────────────────────────────────────────
    t0 = time.time();
    print("[4/8] Loading suppliers...", flush=True);
    for row in read_tbl(tbl_path(data_dir, "supplier.tbl")) {
        n = root ++> Supplier(
            s_suppkey=int(row[0]),
            s_name=row[1].strip(),
            s_address=row[2].strip(),
            s_phone=row[4].strip(),
            s_acctbal=float(row[5]),
            s_comment=row[6].strip()
        );
        supplier_map[int(row[0])] = n[0];
        # Edge: Nation -> Supplier
        nationkey = int(row[3]);
        if nationkey in nation_map {
            nation_map[nationkey] +>: nation_has_supplier() :+> n[0];
        }
    }
    print(f"  ✓ {len(supplier_map)} suppliers ({time.time() - t0:.1f}s)", flush=True);

    # ────────────────────────────────────────────
    #  5. Load CUSTOMER (15,000 rows, FK: C_NATIONKEY -> NATION)
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "customer.tbl"));
    total = len(rows);
    print(f"[5/8] Loading customers (0/{total})...", flush=True);
    count = 0;
    for row in rows {
        n = root ++> Customer(
            c_custkey=int(row[0]),
            c_name=row[1].strip(),
            c_address=row[2].strip(),
            c_phone=row[4].strip(),
            c_acctbal=float(row[5]),
            c_mktsegment=row[6].strip(),
            c_comment=row[7].strip()
        );
        customer_map[int(row[0])] = n[0];
        # Edge: Nation -> Customer
        nationkey = int(row[3]);
        if nationkey in nation_map {
            nation_map[nationkey] +>: nation_has_customer() :+> n[0];
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
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "partsupp.tbl"));
    total = len(rows);
    print(f"[6/8] Loading partsupp (0/{total})...", flush=True);
    ps_count = 0;
    for row in rows {
        partkey = int(row[0]);
        suppkey = int(row[1]);
        n = root ++> PartSupp(
            ps_partkey=partkey,
            ps_suppkey=suppkey,
            ps_availqty=int(row[2]),
            ps_supplycost=float(row[3]),
            ps_comment=row[4].strip()
        );
        composite_key = f"{partkey}_{suppkey}";
        partsupp_map[composite_key] = n[0];
        ps_count += 1;
        # Edge: Part -> PartSupp
        if partkey in part_map {
            part_map[partkey] +>: part_supplied_by() :+> n[0];
        }
        # Edge: Supplier -> PartSupp
        if suppkey in supplier_map {
            supplier_map[suppkey] +>: supplier_supplies() :+> n[0];
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
    # ────────────────────────────────────────────
    t0 = time.time();
    rows = read_tbl(tbl_path(data_dir, "orders.tbl"));
    total = len(rows);
    print(f"[7/8] Loading orders (0/{total})...", flush=True);
    count = 0;
    for row in rows {
        n = root ++> Order(
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
        order_map[int(row[0])] = n[0];
        # Edge: Customer -> Order
        custkey = int(row[1]);
        if custkey in customer_map {
            customer_map[custkey] +>: customer_ordered() :+> n[0];
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
        n = root ++> LineItem(
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
        # Edge: Order -> LineItem
        if orderkey in order_map {
            order_map[orderkey] +>: order_has_lineitem() :+> n[0];
        }
        # Edge: LineItem -> PartSupp
        composite_key = f"{partkey}_{suppkey}";
        if composite_key in partsupp_map {
            n[0] +>: lineitem_partsupp() :+> partsupp_map[composite_key];
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
