"""TPC-H Benchmark: 22 Query Walkers.

Each walker corresponds to one TPC-H query (Q1–Q22).
All walkers spawn on root and use `report` to return results.

Graph hierarchy (from loader):
    root -> Region -[region_has_nation]-> Nation -[nation_has_supplier]-> Supplier
                                                -[nation_has_customer]-> Customer
            Region -> Nation -> Customer -[customer_ordered]-> Order -[order_has_lineitem]-> LineItem
            root -> Part -[part_supplied_by]-> PartSupp
            Supplier -[supplier_supplies]-> PartSupp
            LineItem -[lineitem_partsupp]-> PartSupp
"""

include models;

# ════════════════════════════════════════════════════════════════
#  Q1: Pricing Summary Report
#  Groups lineitems by returnflag/linestatus, computes aggregates.
#  Params: delta (days before 1998-12-01)
# ════════════════════════════════════════════════════════════════
walker Q1_PricingSummary {
    has delta: int = 90;

    can run with Root entry {
        # Compute cutoff date string for comparison (YYYY-MM-DD format)
        import datetime;
        cutoff = (datetime.date(1998, 12, 1) - datetime.timedelta(days=self.delta)).isoformat();

        # Collect all lineitems via: root -> Region -> Nation -> Customer -> Order -> LineItem
        agg: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_shipdate <= cutoff {
                                key = f"{li.l_returnflag}|{li.l_linestatus}";
                                if key not in agg {
                                    agg[key] = {
                                        "l_returnflag": li.l_returnflag,
                                        "l_linestatus": li.l_linestatus,
                                        "sum_qty": 0.0,
                                        "sum_base_price": 0.0,
                                        "sum_disc_price": 0.0,
                                        "sum_charge": 0.0,
                                        "sum_discount": 0.0,
                                        "count": 0
                                    };
                                }
                                rec = agg[key];
                                rec["sum_qty"] += li.l_quantity;
                                rec["sum_base_price"] += li.l_extendedprice;
                                disc_price = li.l_extendedprice * (1.0 - li.l_discount);
                                rec["sum_disc_price"] += disc_price;
                                rec["sum_charge"] += disc_price * (1.0 + li.l_tax);
                                rec["sum_discount"] += li.l_discount;
                                rec["count"] += 1;
                            }
                        }
                    }
                }
            }
        }
        # Compute averages and sort
        results: list = [];
        for (key, rec) in agg.items() {
            cnt = rec["count"];
            results.append({
                "l_returnflag": rec["l_returnflag"],
                "l_linestatus": rec["l_linestatus"],
                "sum_qty": rec["sum_qty"],
                "sum_base_price": rec["sum_base_price"],
                "sum_disc_price": rec["sum_disc_price"],
                "sum_charge": rec["sum_charge"],
                "avg_qty": rec["sum_qty"] / cnt if cnt > 0 else 0.0,
                "avg_price": rec["sum_base_price"] / cnt if cnt > 0 else 0.0,
                "avg_disc": rec["sum_discount"] / cnt if cnt > 0 else 0.0,
                "count_order": cnt
            });
        }
        results.sort(key=lambda x: dict : (x["l_returnflag"], x["l_linestatus"]));
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q2: Minimum Cost Supplier
#  Finds suppliers in a region with min cost for parts of given size/type.
#  Params: size, type_suffix, region_name
# ════════════════════════════════════════════════════════════════
walker Q2_MinCostSupplier {
    has p_size: int = 15,
        p_type_suffix: str = "BRASS",
        region_name: str = "EUROPE";

    can run with Root entry {
        results: list = [];
        # Iterate Parts from root, check partsupp suppliers in target region
        for part in [-->(?:Part)] {
            if part.p_size != self.p_size or not part.p_type.endswith(self.p_type_suffix) {
                continue;
            }
            # Get all PartSupps for this part
            best_cost = 1e18;
            best_rec: dict = {};
            for ps in [part ->:part_supplied_by:->(?:PartSupp)] {
                # Find the supplier for this partsupp
                # Supplier -> PartSupp via supplier_supplies, so reverse: [ps <-:supplier_supplies:<- Supplier]
                suppliers = [ps <-:supplier_supplies:<-(?:Supplier)];
                for supplier in suppliers {
                    # Find nation of supplier
                    nations = [supplier <-:nation_has_supplier:<-(?:Nation)];
                    for nation in nations {
                        regions = [nation <-:region_has_nation:<-(?:Region)];
                        for region in regions {
                            if region.r_name == self.region_name and ps.ps_supplycost < best_cost {
                                best_cost = ps.ps_supplycost;
                                best_rec = {
                                    "s_acctbal": supplier.s_acctbal,
                                    "s_name": supplier.s_name,
                                    "n_name": nation.n_name,
                                    "p_partkey": part.p_partkey,
                                    "p_mfgr": part.p_mfgr,
                                    "s_address": supplier.s_address,
                                    "s_phone": supplier.s_phone,
                                    "s_comment": supplier.s_comment
                                };
                            }
                        }
                    }
                }
            }
            if best_rec {
                results.append(best_rec);
            }
        }
        results.sort(key=lambda x: dict : (-x["s_acctbal"], x["n_name"], x["s_name"], x["p_partkey"]));
        report results[:100];
    }
}

# ════════════════════════════════════════════════════════════════
#  Q3: Shipping Priority
#  Finds unshipped orders for a market segment before a date.
#  Params: segment, date
# ════════════════════════════════════════════════════════════════
walker Q3_ShippingPriority {
    has segment: str = "BUILDING",
        date: str = "1995-03-15";

    can run with Root entry {
        agg: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    if cust.c_mktsegment != self.segment { continue; }
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        if order.o_orderdate >= self.date { continue; }
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_shipdate <= self.date { continue; }
                            key = f"{li.l_orderkey}|{order.o_orderdate}|{order.o_shippriority}";
                            if key not in agg {
                                agg[key] = {
                                    "l_orderkey": li.l_orderkey,
                                    "o_orderdate": order.o_orderdate,
                                    "o_shippriority": order.o_shippriority,
                                    "revenue": 0.0
                                };
                            }
                            agg[key]["revenue"] += li.l_extendedprice * (1.0 - li.l_discount);
                        }
                    }
                }
            }
        }
        results = list(agg.values());
        results.sort(key=lambda x: dict : (-x["revenue"], x["o_orderdate"]));
        report results[:10];
    }
}

# ════════════════════════════════════════════════════════════════
#  Q4: Order Priority Checking
#  Counts orders by priority where at least one lineitem was late.
#  Params: date (start of 3-month window)
# ════════════════════════════════════════════════════════════════
walker Q4_OrderPriority {
    has date: str = "1993-07-01";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_date = (start + datetime.timedelta(days=92)).isoformat();  # ~3 months

        agg: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        if order.o_orderdate < self.date or order.o_orderdate >= end_date {
                            continue;
                        }
                        # Check if any lineitem has commitdate < receiptdate
                        has_late = False;
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_commitdate < li.l_receiptdate {
                                has_late = True;
                                break;
                            }
                        }
                        if has_late {
                            prio = order.o_orderpriority;
                            if prio not in agg {
                                agg[prio] = 0;
                            }
                            agg[prio] += 1;
                        }
                    }
                }
            }
        }
        results = [{"o_orderpriority": k, "order_count": v} for (k, v) in agg.items()];
        results.sort(key=lambda x: dict : x["o_orderpriority"]);
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q5: Local Supplier Volume
#  Revenue by nation for a region in a year.
#  Params: region_name, date
# ════════════════════════════════════════════════════════════════
walker Q5_LocalSupplierVolume {
    has region_name: str = "ASIA",
        date: str = "1994-01-01";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_date = (start.replace(year=start.year + 1)).isoformat();

        # Build nation->supplier_keys set for the target region
        nation_suppliers: dict = {};  # nation_name -> set of suppkeys
        for region in [-->(?:Region)] {
            if region.r_name != self.region_name { continue; }
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                supp_keys: list = [];
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    supp_keys.append(supplier.s_suppkey);
                }
                nation_suppliers[nation.n_name] = supp_keys;
            }
        }

        # Now scan orders/lineitems for customers in the same nations
        agg: dict = {};
        for region in [-->(?:Region)] {
            if region.r_name != self.region_name { continue; }
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                n_name = nation.n_name;
                supp_keys = nation_suppliers.get(n_name, []);
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        if order.o_orderdate < self.date or order.o_orderdate >= end_date {
                            continue;
                        }
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            # Supplier must be in the same nation
                            if li.l_suppkey in supp_keys {
                                if n_name not in agg {
                                    agg[n_name] = 0.0;
                                }
                                agg[n_name] += li.l_extendedprice * (1.0 - li.l_discount);
                            }
                        }
                    }
                }
            }
        }
        results = [{"n_name": k, "revenue": v} for (k, v) in agg.items()];
        results.sort(key=lambda x: dict : -x["revenue"]);
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q6: Forecasting Revenue Change
#  Sum of discounted revenue for lineitems in a date/discount/qty range.
#  Params: date, discount, quantity
# ════════════════════════════════════════════════════════════════
walker Q6_ForecastingRevenue {
    has date: str = "1994-01-01",
        discount: float = 0.06,
        quantity: float = 24.0;

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_date = (start.replace(year=start.year + 1)).isoformat();
        lo_disc = self.discount - 0.01;
        hi_disc = self.discount + 0.01;

        revenue = 0.0;
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if (li.l_shipdate >= self.date
                                and li.l_shipdate < end_date
                                and li.l_discount >= lo_disc
                                and li.l_discount <= hi_disc
                                and li.l_quantity < self.quantity) {
                                revenue += li.l_extendedprice * li.l_discount;
                            }
                        }
                    }
                }
            }
        }
        report {"revenue": revenue};
    }
}

# ════════════════════════════════════════════════════════════════
#  Q7: Volume Shipping
#  Revenue between two nations by year.
#  Params: nation1, nation2
# ════════════════════════════════════════════════════════════════
walker Q7_VolumeShipping {
    has nation1: str = "FRANCE",
        nation2: str = "GERMANY";

    can run with Root entry {
        # Build suppkey -> nation_name map
        supp_nation: dict = {};
        cust_nation: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                if nation.n_name != self.nation1 and nation.n_name != self.nation2 {
                    continue;
                }
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    supp_nation[supplier.s_suppkey] = nation.n_name;
                }
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    cust_nation[cust.c_custkey] = nation.n_name;
                }
            }
        }

        agg: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                if nation.n_name != self.nation1 and nation.n_name != self.nation2 {
                    continue;
                }
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    c_nat = cust_nation.get(cust.c_custkey, "");
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            s_nat = supp_nation.get(li.l_suppkey, "");
                            if li.l_shipdate >= "1995-01-01" and li.l_shipdate <= "1996-12-31" {
                                if ((s_nat == self.nation1 and c_nat == self.nation2)
                                    or (s_nat == self.nation2 and c_nat == self.nation1)) {
                                    l_year = li.l_shipdate[:4];
                                    key = f"{s_nat}|{c_nat}|{l_year}";
                                    if key not in agg {
                                        agg[key] = {
                                            "supp_nation": s_nat,
                                            "cust_nation": c_nat,
                                            "l_year": l_year,
                                            "revenue": 0.0
                                        };
                                    }
                                    agg[key]["revenue"] += li.l_extendedprice * (1.0 - li.l_discount);
                                }
                            }
                        }
                    }
                }
            }
        }
        results = list(agg.values());
        results.sort(key=lambda x: dict : (x["supp_nation"], x["cust_nation"], x["l_year"]));
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q8: National Market Share
#  Market share of a nation within a region for a part type.
#  Params: nation_name, region_name, p_type
# ════════════════════════════════════════════════════════════════
walker Q8_NationalMarketShare {
    has nation_name: str = "BRAZIL",
        region_name: str = "AMERICA",
        p_type: str = "ECONOMY ANODIZED STEEL";

    can run with Root entry {
        # Build suppkey -> nation_name map
        supp_nation: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    supp_nation[supplier.s_suppkey] = nation.n_name;
                }
            }
        }

        # Build set of partkeys matching the type
        matching_parts: dict = {};
        for part in [-->(?:Part)] {
            if part.p_type == self.p_type {
                matching_parts[part.p_partkey] = True;
            }
        }

        # Scan orders from customers in the target region
        agg: dict = {};  # year -> {total_volume, nation_volume}
        for region in [-->(?:Region)] {
            if region.r_name != self.region_name { continue; }
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        if order.o_orderdate < "1995-01-01" or order.o_orderdate > "1996-12-31" {
                            continue;
                        }
                        o_year = order.o_orderdate[:4];
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_partkey not in matching_parts {
                                continue;
                            }
                            volume = li.l_extendedprice * (1.0 - li.l_discount);
                            if o_year not in agg {
                                agg[o_year] = {"total": 0.0, "nation": 0.0};
                            }
                            agg[o_year]["total"] += volume;
                            s_nat = supp_nation.get(li.l_suppkey, "");
                            if s_nat == self.nation_name {
                                agg[o_year]["nation"] += volume;
                            }
                        }
                    }
                }
            }
        }
        results: list = [];
        for (year, val) in sorted(agg.items()) {
            mkt_share = val["nation"] / val["total"] if val["total"] > 0 else 0.0;
            results.append({"o_year": year, "mkt_share": mkt_share});
        }
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q9: Product Type Profit Measure
#  Profit by nation and year for parts matching a name pattern.
#  Params: color (substring of part name)
# ════════════════════════════════════════════════════════════════
walker Q9_ProductTypeProfit {
    has color: str = "green";

    can run with Root entry {
        # Build lookup maps
        supp_nation: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    supp_nation[supplier.s_suppkey] = nation.n_name;
                }
            }
        }

        # Build partkey -> True for matching parts
        matching_parts: dict = {};
        # Also build (partkey, suppkey) -> supplycost
        ps_cost: dict = {};
        for part in [-->(?:Part)] {
            if self.color in part.p_name {
                matching_parts[part.p_partkey] = True;
                for ps in [part ->:part_supplied_by:->(?:PartSupp)] {
                    ps_cost[f"{ps.ps_partkey}_{ps.ps_suppkey}"] = ps.ps_supplycost;
                }
            }
        }

        agg: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        o_year = order.o_orderdate[:4];
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_partkey not in matching_parts { continue; }
                            s_nat = supp_nation.get(li.l_suppkey, "");
                            if s_nat == "" { continue; }
                            cost_key = f"{li.l_partkey}_{li.l_suppkey}";
                            supplycost = ps_cost.get(cost_key, 0.0);
                            amount = li.l_extendedprice * (1.0 - li.l_discount) - supplycost * li.l_quantity;
                            key = f"{s_nat}|{o_year}";
                            if key not in agg {
                                agg[key] = {"nation": s_nat, "o_year": o_year, "sum_profit": 0.0};
                            }
                            agg[key]["sum_profit"] += amount;
                        }
                    }
                }
            }
        }
        results = list(agg.values());
        results.sort(key=lambda x: dict : (x["nation"], -int(x["o_year"]) if x["o_year"].lstrip("-").isdigit() else 0));
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q10: Returned Item Reporting
#  Top customers by revenue of returned items in a date window.
#  Params: date
# ════════════════════════════════════════════════════════════════
walker Q10_ReturnedItemReporting {
    has date: str = "1993-10-01";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_date = (start + datetime.timedelta(days=92)).isoformat();

        results: list = [];
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    revenue = 0.0;
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        if order.o_orderdate < self.date or order.o_orderdate >= end_date {
                            continue;
                        }
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_returnflag == "R" {
                                revenue += li.l_extendedprice * (1.0 - li.l_discount);
                            }
                        }
                    }
                    if revenue > 0.0 {
                        results.append({
                            "c_custkey": cust.c_custkey,
                            "c_name": cust.c_name,
                            "revenue": revenue,
                            "c_acctbal": cust.c_acctbal,
                            "n_name": nation.n_name,
                            "c_address": cust.c_address,
                            "c_phone": cust.c_phone,
                            "c_comment": cust.c_comment
                        });
                    }
                }
            }
        }
        results.sort(key=lambda x: dict : -x["revenue"]);
        report results[:20];
    }
}

# ════════════════════════════════════════════════════════════════
#  Q11: Important Stock Identification
#  PartSupp values above a threshold for suppliers in a nation.
#  Params: nation_name, fraction
# ════════════════════════════════════════════════════════════════
walker Q11_ImportantStock {
    has nation_name: str = "GERMANY",
        fraction: float = 0.0001;

    can run with Root entry {
        # Find suppliers in the target nation
        target_suppkeys: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                if nation.n_name == self.nation_name {
                    for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                        target_suppkeys[supplier.s_suppkey] = True;
                    }
                }
            }
        }

        # Scan all PartSupps via Parts
        ps_values: dict = {};  # partkey -> total value
        total_value = 0.0;
        for part in [-->(?:Part)] {
            for ps in [part ->:part_supplied_by:->(?:PartSupp)] {
                if ps.ps_suppkey in target_suppkeys {
                    val = ps.ps_supplycost * ps.ps_availqty;
                    total_value += val;
                    if ps.ps_partkey not in ps_values {
                        ps_values[ps.ps_partkey] = 0.0;
                    }
                    ps_values[ps.ps_partkey] += val;
                }
            }
        }

        threshold = total_value * self.fraction;
        results = [
            {"ps_partkey": k, "value": v}
            for (k, v) in ps_values.items()
            if v > threshold
        ];
        results.sort(key=lambda x: dict : -x["value"]);
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q12: Shipping Modes and Order Priority
#  Counts high/low priority orders by ship mode for late deliveries.
#  Params: shipmode1, shipmode2, date
# ════════════════════════════════════════════════════════════════
walker Q12_ShippingModes {
    has shipmode1: str = "MAIL",
        shipmode2: str = "SHIP",
        date: str = "1994-01-01";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_date = (start.replace(year=start.year + 1)).isoformat();

        agg: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if ((li.l_shipmode == self.shipmode1 or li.l_shipmode == self.shipmode2)
                                and li.l_commitdate < li.l_receiptdate
                                and li.l_shipdate < li.l_commitdate
                                and li.l_receiptdate >= self.date
                                and li.l_receiptdate < end_date) {
                                mode = li.l_shipmode;
                                if mode not in agg {
                                    agg[mode] = {"high_line_count": 0, "low_line_count": 0};
                                }
                                if order.o_orderpriority == "1-URGENT" or order.o_orderpriority == "2-HIGH" {
                                    agg[mode]["high_line_count"] += 1;
                                } else {
                                    agg[mode]["low_line_count"] += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        results = [
            {"l_shipmode": k, "high_line_count": v["high_line_count"], "low_line_count": v["low_line_count"]}
            for (k, v) in agg.items()
        ];
        results.sort(key=lambda x: dict : x["l_shipmode"]);
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q13: Customer Distribution
#  Distribution of customers by order count (excluding special comments).
#  Params: word1, word2
# ════════════════════════════════════════════════════════════════
walker Q13_CustomerDistribution {
    has word1: str = "special",
        word2: str = "requests";

    can run with Root entry {
        # Count orders per customer, excluding orders with matching comment
        cust_order_counts: list = [];
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    count = 0;
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        # Exclude orders whose comment matches '%word1%word2%'
                        comment = order.o_comment;
                        idx1 = comment.find(self.word1);
                        if idx1 >= 0 and comment.find(self.word2, idx1 + len(self.word1)) >= 0 {
                            continue;
                        }
                        count += 1;
                    }
                    cust_order_counts.append(count);
                }
            }
        }
        # Group by count
        dist: dict = {};
        for c in cust_order_counts {
            if c not in dist {
                dist[c] = 0;
            }
            dist[c] += 1;
        }
        results = [{"c_count": k, "custdist": v} for (k, v) in dist.items()];
        results.sort(key=lambda x: dict : (-x["custdist"], -x["c_count"]));
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q14: Promotion Effect
#  Percentage of revenue from promotional parts in a month.
#  Params: date
# ════════════════════════════════════════════════════════════════
walker Q14_PromotionEffect {
    has date: str = "1995-09-01";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        if start.month == 12 {
            end_date = start.replace(year=start.year + 1, month=1).isoformat();
        } else {
            end_date = start.replace(month=start.month + 1).isoformat();
        }

        # Build partkey -> p_type map
        part_types: dict = {};
        for part in [-->(?:Part)] {
            part_types[part.p_partkey] = part.p_type;
        }

        promo_revenue = 0.0;
        total_revenue = 0.0;
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_shipdate >= self.date and li.l_shipdate < end_date {
                                rev = li.l_extendedprice * (1.0 - li.l_discount);
                                total_revenue += rev;
                                p_type = part_types.get(li.l_partkey, "");
                                if p_type.startswith("PROMO") {
                                    promo_revenue += rev;
                                }
                            }
                        }
                    }
                }
            }
        }
        result = 100.0 * promo_revenue / total_revenue if total_revenue > 0 else 0.0;
        report {"promo_revenue": result};
    }
}

# ════════════════════════════════════════════════════════════════
#  Q15: Top Supplier
#  Supplier with maximum revenue in a 3-month window.
#  Params: date
# ════════════════════════════════════════════════════════════════
walker Q15_TopSupplier {
    has date: str = "1996-01-01";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_month = start.month + 3;
        end_year = start.year;
        if end_month > 12 {
            end_month -= 12;
            end_year += 1;
        }
        end_date = datetime.date(end_year, end_month, 1).isoformat();

        # Compute revenue per supplier from lineitems
        supp_revenue: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_shipdate >= self.date and li.l_shipdate < end_date {
                                suppkey = li.l_suppkey;
                                if suppkey not in supp_revenue {
                                    supp_revenue[suppkey] = 0.0;
                                }
                                supp_revenue[suppkey] += li.l_extendedprice * (1.0 - li.l_discount);
                            }
                        }
                    }
                }
            }
        }

        if not supp_revenue {
            report [];
            return;
        }

        max_rev = max(supp_revenue.values());

        # Find suppliers with max revenue
        supp_map: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    supp_map[supplier.s_suppkey] = supplier;
                }
            }
        }

        results: list = [];
        for (sk, rev) in supp_revenue.items() {
            if rev == max_rev and sk in supp_map {
                s = supp_map[sk];
                results.append({
                    "s_suppkey": s.s_suppkey,
                    "s_name": s.s_name,
                    "s_address": s.s_address,
                    "s_phone": s.s_phone,
                    "total_revenue": rev
                });
            }
        }
        results.sort(key=lambda x: dict : x["s_suppkey"]);
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q16: Parts/Supplier Relationship
#  Count of distinct suppliers per part brand/type/size combo.
#  Params: brand, type_prefix, sizes (list)
# ════════════════════════════════════════════════════════════════
walker Q16_PartsSupplierRelation {
    has brand: str = "Brand#45",
        type_prefix: str = "MEDIUM POLISHED",
        sizes: list = [49, 14, 23, 45, 19, 3, 36, 9];

    can run with Root entry {
        # Find suppliers with complaints
        complaint_suppkeys: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    if "Customer" in supplier.s_comment and "Complaints" in supplier.s_comment {
                        complaint_suppkeys[supplier.s_suppkey] = True;
                    }
                }
            }
        }

        agg: dict = {};
        for part in [-->(?:Part)] {
            if (part.p_brand != self.brand
                and not part.p_type.startswith(self.type_prefix)
                and part.p_size in self.sizes) {
                key = f"{part.p_brand}|{part.p_type}|{part.p_size}";
                if key not in agg {
                    agg[key] = {
                        "p_brand": part.p_brand,
                        "p_type": part.p_type,
                        "p_size": part.p_size,
                        "suppkeys": {}
                    };
                }
                for ps in [part ->:part_supplied_by:->(?:PartSupp)] {
                    if ps.ps_suppkey not in complaint_suppkeys {
                        agg[key]["suppkeys"][ps.ps_suppkey] = True;
                    }
                }
            }
        }
        results = [
            {
                "p_brand": v["p_brand"],
                "p_type": v["p_type"],
                "p_size": v["p_size"],
                "supplier_cnt": len(v["suppkeys"])
            }
            for (k, v) in agg.items()
        ];
        results.sort(key=lambda x: dict : (-x["supplier_cnt"], x["p_brand"], x["p_type"], x["p_size"]));
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q17: Small-Quantity-Order Revenue
#  Average yearly revenue for parts with small orders.
#  Params: brand, container
# ════════════════════════════════════════════════════════════════
walker Q17_SmallQuantityOrder {
    has brand: str = "Brand#23",
        container: str = "MED BOX";

    can run with Root entry {
        # Find matching parts and compute avg qty per part from lineitems
        # First pass: collect all lineitem quantities per matching partkey
        part_qtys: dict = {};  # partkey -> [quantities]
        matching_partkeys: dict = {};
        for part in [-->(?:Part)] {
            if part.p_brand == self.brand and part.p_container == self.container {
                matching_partkeys[part.p_partkey] = True;
                part_qtys[part.p_partkey] = [];
            }
        }

        # Scan all lineitems to collect quantities
        total_revenue = 0.0;
        li_data: list = [];  # collect (partkey, quantity, extendedprice)
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if li.l_partkey in matching_partkeys {
                                part_qtys[li.l_partkey].append(li.l_quantity);
                                li_data.append([li.l_partkey, li.l_quantity, li.l_extendedprice]);
                            }
                        }
                    }
                }
            }
        }

        # Compute avg qty per part
        part_avg: dict = {};
        for (pk, qtys) in part_qtys.items() {
            if len(qtys) > 0 {
                part_avg[pk] = sum(qtys) / len(qtys);
            }
        }

        # Sum revenue where qty < 0.2 * avg
        for item in li_data {
            pk = item[0];
            qty = item[1];
            price = item[2];
            avg = part_avg.get(pk, 0.0);
            if qty < 0.2 * avg {
                total_revenue += price;
            }
        }

        report {"avg_yearly": total_revenue / 7.0};
    }
}

# ════════════════════════════════════════════════════════════════
#  Q18: Large Volume Customer
#  Customers with orders having large total quantity.
#  Params: quantity_threshold
# ════════════════════════════════════════════════════════════════
walker Q18_LargeVolumeCustomer {
    has quantity_threshold: float = 300.0;

    can run with Root entry {
        results: list = [];
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        total_qty = 0.0;
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            total_qty += li.l_quantity;
                        }
                        if total_qty > self.quantity_threshold {
                            results.append({
                                "c_name": cust.c_name,
                                "c_custkey": cust.c_custkey,
                                "o_orderkey": order.o_orderkey,
                                "o_orderdate": order.o_orderdate,
                                "o_totalprice": order.o_totalprice,
                                "sum_quantity": total_qty
                            });
                        }
                    }
                }
            }
        }
        results.sort(key=lambda x: dict : (-x["o_totalprice"], x["o_orderdate"]));
        report results[:100];
    }
}

# ════════════════════════════════════════════════════════════════
#  Q19: Discounted Revenue
#  Revenue for lineitems matching specific brand/container/quantity criteria.
#  Params: brand1, brand2, brand3, quantity1, quantity2, quantity3
# ════════════════════════════════════════════════════════════════
walker Q19_DiscountedRevenue {
    has brand1: str = "Brand#12",
        brand2: str = "Brand#23",
        brand3: str = "Brand#34",
        quantity1: float = 1.0,
        quantity2: float = 10.0,
        quantity3: float = 20.0;

    can run with Root entry {
        # Build partkey -> part info map
        part_info: dict = {};
        for part in [-->(?:Part)] {
            part_info[part.p_partkey] = {
                "brand": part.p_brand,
                "container": part.p_container,
                "size": part.p_size
            };
        }

        sm_containers = ["SM CASE", "SM BOX", "SM PACK", "SM PKG"];
        med_containers = ["MED BAG", "MED BOX", "MED PKG", "MED PACK"];
        lg_containers = ["LG CASE", "LG BOX", "LG PACK", "LG PKG"];

        revenue = 0.0;
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if (li.l_shipmode not in ["AIR", "AIR REG"]
                                or li.l_shipinstruct != "DELIVER IN PERSON") {
                                continue;
                            }
                            pi = part_info.get(li.l_partkey, {});
                            if not pi { continue; }
                            matched = False;
                            if (pi["brand"] == self.brand1
                                and pi["container"] in sm_containers
                                and li.l_quantity >= self.quantity1
                                and li.l_quantity <= self.quantity1 + 10
                                and pi["size"] >= 1 and pi["size"] <= 5) {
                                matched = True;
                            } elif (pi["brand"] == self.brand2
                                and pi["container"] in med_containers
                                and li.l_quantity >= self.quantity2
                                and li.l_quantity <= self.quantity2 + 10
                                and pi["size"] >= 1 and pi["size"] <= 10) {
                                matched = True;
                            } elif (pi["brand"] == self.brand3
                                and pi["container"] in lg_containers
                                and li.l_quantity >= self.quantity3
                                and li.l_quantity <= self.quantity3 + 10
                                and pi["size"] >= 1 and pi["size"] <= 15) {
                                matched = True;
                            }
                            if matched {
                                revenue += li.l_extendedprice * (1.0 - li.l_discount);
                            }
                        }
                    }
                }
            }
        }
        report {"revenue": revenue};
    }
}

# ════════════════════════════════════════════════════════════════
#  Q20: Potential Part Promotion
#  Suppliers in a nation with excess stock for parts matching a name.
#  Params: color, date, nation_name
# ════════════════════════════════════════════════════════════════
walker Q20_PotentialPartPromotion {
    has color: str = "forest",
        date: str = "1994-01-01",
        nation_name: str = "CANADA";

    can run with Root entry {
        import datetime;
        start = datetime.date.fromisoformat(self.date);
        end_date = start.replace(year=start.year + 1).isoformat();

        # Find partkeys matching the color
        matching_partkeys: dict = {};
        for part in [-->(?:Part)] {
            if part.p_name.startswith(self.color) {
                matching_partkeys[part.p_partkey] = True;
            }
        }

        # Collect lineitem quantities per (partkey, suppkey) in date range
        li_qtys: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        for li in [order ->:order_has_lineitem:->(?:LineItem)] {
                            if (li.l_partkey in matching_partkeys
                                and li.l_shipdate >= self.date
                                and li.l_shipdate < end_date) {
                                key = f"{li.l_partkey}_{li.l_suppkey}";
                                if key not in li_qtys {
                                    li_qtys[key] = 0.0;
                                }
                                li_qtys[key] += li.l_quantity;
                            }
                        }
                    }
                }
            }
        }

        # Find qualifying suppliers in the target nation
        qualifying_suppkeys: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                if nation.n_name != self.nation_name { continue; }
                for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                    for ps in [supplier ->:supplier_supplies:->(?:PartSupp)] {
                        if ps.ps_partkey in matching_partkeys {
                            key = f"{ps.ps_partkey}_{ps.ps_suppkey}";
                            threshold = 0.5 * li_qtys.get(key, 0.0);
                            if ps.ps_availqty > threshold {
                                qualifying_suppkeys[supplier.s_suppkey] = supplier;
                            }
                        }
                    }
                }
            }
        }

        results = [
            {"s_name": s.s_name, "s_address": s.s_address}
            for s in qualifying_suppkeys.values()
        ];
        results.sort(key=lambda x: dict : x["s_name"]);
        report results;
    }
}

# ════════════════════════════════════════════════════════════════
#  Q21: Suppliers Who Kept Orders Waiting
#  Suppliers in a nation with multi-supplier orders where only they were late.
#  Params: nation_name
# ════════════════════════════════════════════════════════════════
walker Q21_SuppliersWhoKeptOrdersWaiting {
    has nation_name: str = "SAUDI ARABIA";

    can run with Root entry {
        # Find suppkeys in target nation
        target_suppliers: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                if nation.n_name == self.nation_name {
                    for supplier in [nation ->:nation_has_supplier:->(?:Supplier)] {
                        target_suppliers[supplier.s_suppkey] = supplier.s_name;
                    }
                }
            }
        }

        supp_counts: dict = {};
        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    for order in [cust ->:customer_ordered:->(?:Order)] {
                        if order.o_orderstatus != "F" { continue; }
                        lineitems = [order ->:order_has_lineitem:->(?:LineItem)];
                        # Get all suppkeys and late suppkeys for this order
                        all_suppkeys: dict = {};
                        late_suppkeys: dict = {};
                        for li in lineitems {
                            all_suppkeys[li.l_suppkey] = True;
                            if li.l_receiptdate > li.l_commitdate {
                                late_suppkeys[li.l_suppkey] = True;
                            }
                        }
                        # Check: multi-supplier order, exactly one late supplier from target
                        for sk in late_suppkeys {
                            if sk not in target_suppliers { continue; }
                            # Must exist another supplier
                            has_other = False;
                            for osk in all_suppkeys {
                                if osk != sk {
                                    has_other = True;
                                    break;
                                }
                            }
                            if not has_other { continue; }
                            # Must NOT exist another late supplier
                            other_late = False;
                            for osk in late_suppkeys {
                                if osk != sk {
                                    other_late = True;
                                    break;
                                }
                            }
                            if other_late { continue; }
                            if sk not in supp_counts {
                                supp_counts[sk] = 0;
                            }
                            supp_counts[sk] += 1;
                        }
                    }
                }
            }
        }

        results = [
            {"s_name": target_suppliers[sk], "numwait": cnt}
            for (sk, cnt) in supp_counts.items()
        ];
        results.sort(key=lambda x: dict : (-x["numwait"], x["s_name"]));
        report results[:100];
    }
}

# ════════════════════════════════════════════════════════════════
#  Q22: Global Sales Opportunity
#  Customers with high balances but no orders, grouped by country code.
#  Params: country_codes (list of 2-digit phone prefixes)
# ════════════════════════════════════════════════════════════════
walker Q22_GlobalSalesOpportunity {
    has country_codes: list = ["13", "31", "23", "29", "30", "18", "17"];

    can run with Root entry {
        # First pass: compute average acctbal for positive-balance customers with matching codes
        sum_bal = 0.0;
        count_bal = 0;
        all_customers: list = [];

        for region in [-->(?:Region)] {
            for nation in [region ->:region_has_nation:->(?:Nation)] {
                for cust in [nation ->:nation_has_customer:->(?:Customer)] {
                    cntrycode = cust.c_phone[:2];
                    if cntrycode in self.country_codes {
                        all_customers.append(cust);
                        if cust.c_acctbal > 0.0 {
                            sum_bal += cust.c_acctbal;
                            count_bal += 1;
                        }
                    }
                }
            }
        }

        avg_bal = sum_bal / count_bal if count_bal > 0 else 0.0;

        # Second pass: find customers above avg with no orders
        agg: dict = {};
        for cust in all_customers {
            if cust.c_acctbal <= avg_bal { continue; }
            # Check if customer has any orders
            orders = [cust ->:customer_ordered:->(?:Order)];
            if len(orders) > 0 { continue; }
            cntrycode = cust.c_phone[:2];
            if cntrycode not in agg {
                agg[cntrycode] = {"numcust": 0, "totacctbal": 0.0};
            }
            agg[cntrycode]["numcust"] += 1;
            agg[cntrycode]["totacctbal"] += cust.c_acctbal;
        }

        results = [
            {"cntrycode": k, "numcust": v["numcust"], "totacctbal": v["totacctbal"]}
            for (k, v) in agg.items()
        ];
        results.sort(key=lambda x: dict : x["cntrycode"]);
        report results;
    }
}
