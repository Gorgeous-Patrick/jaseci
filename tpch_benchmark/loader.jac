"""TPC-H Benchmark: Data loader.

Reads pipe-delimited .tbl files from the tpch/ directory and constructs
the full TPC-H graph — nodes for every row and edges for every foreign
key relationship.
"""

import os;

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
    #  1. Load REGION
    # ────────────────────────────────────────────
    print("Loading regions...");
    for row in read_tbl(tbl_path(data_dir, "region.tbl")) {
        n = root ++> Region(
            r_regionkey=int(row[0]),
            r_name=row[1].strip(),
            r_comment=row[2].strip()
        );
        region_map[int(row[0])] = n[0];
    }
    print(f"  Loaded {len(region_map)} regions");

    # ────────────────────────────────────────────
    #  2. Load NATION  (FK: N_REGIONKEY -> REGION)
    # ────────────────────────────────────────────
    print("Loading nations...");
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
    print(f"  Loaded {len(nation_map)} nations");

    # ────────────────────────────────────────────
    #  3. Load PART
    # ────────────────────────────────────────────
    print("Loading parts...");
    for row in read_tbl(tbl_path(data_dir, "part.tbl")) {
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
    }
    print(f"  Loaded {len(part_map)} parts");

    # ────────────────────────────────────────────
    #  4. Load SUPPLIER  (FK: S_NATIONKEY -> NATION)
    # ────────────────────────────────────────────
    print("Loading suppliers...");
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
    print(f"  Loaded {len(supplier_map)} suppliers");

    # ────────────────────────────────────────────
    #  5. Load CUSTOMER  (FK: C_NATIONKEY -> NATION)
    # ────────────────────────────────────────────
    print("Loading customers...");
    for row in read_tbl(tbl_path(data_dir, "customer.tbl")) {
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
    }
    print(f"  Loaded {len(customer_map)} customers");

    # ────────────────────────────────────────────
    #  6. Load PARTSUPP  (FK: PS_PARTKEY -> PART, PS_SUPPKEY -> SUPPLIER)
    # ────────────────────────────────────────────
    print("Loading partsupp...");
    ps_count = 0;
    for row in read_tbl(tbl_path(data_dir, "partsupp.tbl")) {
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
    }
    print(f"  Loaded {ps_count} partsupp records");

    # ────────────────────────────────────────────
    #  7. Load ORDERS  (FK: O_CUSTKEY -> CUSTOMER)
    # ────────────────────────────────────────────
    print("Loading orders...");
    for row in read_tbl(tbl_path(data_dir, "orders.tbl")) {
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
    }
    print(f"  Loaded {len(order_map)} orders");

    # ────────────────────────────────────────────
    #  8. Load LINEITEM  (FK: L_ORDERKEY -> ORDERS,
    #                      L_PARTKEY+L_SUPPKEY -> PARTSUPP)
    # ────────────────────────────────────────────
    print("Loading lineitems...");
    li_count = 0;
    for row in read_tbl(tbl_path(data_dir, "lineitem.tbl")) {
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
    }
    print(f"  Loaded {li_count} lineitems");

    print("\nTPC-H graph construction complete!");
    print(f"  Total nodes: {len(region_map) + len(nation_map) + len(part_map) + len(supplier_map) + len(customer_map) + ps_count + len(order_map) + li_count}");
}
