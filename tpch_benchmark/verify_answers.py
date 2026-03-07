"""TPC-H answer verification.

Reads expected output from the tpch/answers/ directory and compares
against walker-reported results. Each query answer file is a
pipe-delimited text file with a header row and data rows.

Usage from Jac (after running a walker):
    import:py verify_answers {check_query};
    result = root spawn Q1_PricingSummary();
    check_query(1, result, "/path/to/tpch/answers");

Or standalone Python:
    from verify_answers import check_query, parse_answer_file
"""

import os
from typing import Any

# Positional column mapping: answer file headers don't always match walker
# dict keys (e.g. Q1 has "l|l", Q3 has "o_orderdat", Q18 has "col6").
QUERY_COLUMNS: dict[int, list[str]] = {
    1: ["l_returnflag", "l_linestatus", "sum_qty", "sum_base_price",
        "sum_disc_price", "sum_charge", "avg_qty", "avg_price",
        "avg_disc", "count_order"],
    2: ["s_acctbal", "s_name", "n_name", "p_partkey", "p_mfgr",
        "s_address", "s_phone", "s_comment"],
    3: ["l_orderkey", "revenue", "o_orderdate", "o_shippriority"],
    4: ["o_orderpriority", "order_count"],
    5: ["n_name", "revenue"],
    6: ["revenue"],
    7: ["supp_nation", "cust_nation", "l_year", "revenue"],
    8: ["o_year", "mkt_share"],
    9: ["nation", "o_year", "sum_profit"],
    10: ["c_custkey", "c_name", "revenue", "c_acctbal", "n_name",
         "c_address", "c_phone", "c_comment"],
    11: ["ps_partkey", "value"],
    12: ["l_shipmode", "high_line_count", "low_line_count"],
    13: ["c_count", "custdist"],
    14: ["promo_revenue"],
    15: ["s_suppkey", "s_name", "s_address", "s_phone", "total_revenue"],
    16: ["p_brand", "p_type", "p_size", "supplier_cnt"],
    17: ["avg_yearly"],
    18: ["c_name", "c_custkey", "o_orderkey", "o_orderdate",
         "o_totalprice", "sum_quantity"],
    19: ["revenue"],
    20: ["s_name", "s_address"],
    21: ["s_name", "numwait"],
    22: ["cntrycode", "numcust", "totacctbal"],
}

FLOAT_TOLERANCE = 0.02


def parse_answer_file(filepath: str) -> list[list[str]]:
    """Parse a TPC-H answer .out file into a list of row values.

    The first line is the header (pipe-separated, space-padded column
    names).  Subsequent non-empty lines are pipe-separated data rows.

    Returns a list of lists, where each inner list contains the stripped
    string values for that row (positional, not keyed by header name,
    because some answer files have duplicate header names like Q1's "l|l").
    """
    with open(filepath, "r") as f:
        lines = f.readlines()

    if not lines:
        return []

    rows: list[list[str]] = []
    for line in lines[1:]:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        fields = [f.strip() for f in line.split("|")]
        rows.append(fields)

    return rows


def _coerce_value(val: Any) -> Any:
    """Try to coerce a value to int or float for comparison."""
    if isinstance(val, (int, float)):
        return val
    if isinstance(val, str):
        val = val.strip()
        try:
            return int(val)
        except ValueError:
            pass
        try:
            return float(val)
        except ValueError:
            pass
    return val


def _values_match(expected: Any, actual: Any, col_name: str) -> tuple[bool, str]:
    """Compare an expected value (from answer file) with an actual value.

    Returns (match: bool, detail: str).
    """
    exp = _coerce_value(expected)
    act = _coerce_value(actual)

    if isinstance(exp, (int, float)) and isinstance(act, (int, float)):
        if isinstance(exp, int) and isinstance(act, int):
            if exp == act:
                return True, ""
            return False, f"{col_name}: expected {exp}, got {act}"
        exp_f = float(exp)
        act_f = float(act)
        if abs(exp_f - act_f) <= FLOAT_TOLERANCE:
            return True, ""
        if exp_f != 0 and abs((exp_f - act_f) / exp_f) <= 1e-4:
            return True, ""
        return False, f"{col_name}: expected {exp_f:.2f}, got {act_f:.2f} (diff={abs(exp_f - act_f):.4f})"

    exp_s = str(exp).strip()
    act_s = str(act).strip()
    if exp_s == act_s:
        return True, ""
    return False, f"{col_name}: expected '{exp_s}', got '{act_s}'"


def check_query(
    query_num: int,
    walker_result: Any,
    answers_dir: str,
    verbose: bool = False,
) -> dict[str, Any]:
    """Verify a walker's reported result against the expected TPC-H answer.

    Args:
        query_num: Query number (1–22).
        walker_result: The object reported by the walker. This is either:
            - A list of dicts (for multi-row queries)
            - A single dict (for single-row queries like Q6, Q14, Q17, Q19)
            The walker's ``report`` statement produces a list; if the walker
            reports a single dict, wrap it in a list or pass it directly.
        answers_dir: Path to the directory containing q1.out … q22.out.
        verbose: If True, print detailed comparison info.

    Returns:
        A dict with keys:
            "pass": bool — whether the result matches the expected answer
            "query": int — the query number
            "expected_rows": int — number of expected rows
            "actual_rows": int — number of actual rows
            "mismatches": list[str] — descriptions of mismatched values
            "missing_rows": int — rows in expected but not in actual
            "extra_rows": int — rows in actual but not in expected
    """
    if query_num not in QUERY_COLUMNS:
        return {
            "pass": False,
            "query": query_num,
            "expected_rows": 0,
            "actual_rows": 0,
            "mismatches": [f"Unknown query number: {query_num}"],
            "missing_rows": 0,
            "extra_rows": 0,
        }

    columns = QUERY_COLUMNS[query_num]

    answer_file = os.path.join(answers_dir, f"q{query_num}.out")
    if not os.path.isfile(answer_file):
        return {
            "pass": False,
            "query": query_num,
            "expected_rows": 0,
            "actual_rows": 0,
            "mismatches": [f"Answer file not found: {answer_file}"],
            "missing_rows": 0,
            "extra_rows": 0,
        }

    expected_raw = parse_answer_file(answer_file)

    expected_rows: list[dict[str, Any]] = []
    for raw_row in expected_raw:
        row: dict[str, Any] = {}
        for i, col in enumerate(columns):
            if i < len(raw_row):
                row[col] = raw_row[i]
            else:
                row[col] = ""
        expected_rows.append(row)

    actual_rows: list[dict[str, Any]] = []
    if isinstance(walker_result, list):
        for item in walker_result:
            if isinstance(item, dict):
                actual_rows.append(item)
            elif isinstance(item, list):
                for sub in item:
                    if isinstance(sub, dict):
                        actual_rows.append(sub)
        if len(actual_rows) == 0 and len(walker_result) == 1 and isinstance(walker_result[0], list):
            for sub in walker_result[0]:
                if isinstance(sub, dict):
                    actual_rows.append(sub)
    elif isinstance(walker_result, dict):
        actual_rows.append(walker_result)

    mismatches: list[str] = []

    if len(expected_rows) != len(actual_rows):
        mismatches.append(
            f"Row count mismatch: expected {len(expected_rows)}, got {len(actual_rows)}"
        )

    compare_count = min(len(expected_rows), len(actual_rows))
    for i in range(compare_count):
        exp_row = expected_rows[i]
        act_row = actual_rows[i]
        for col in columns:
            exp_val = exp_row.get(col, "")
            act_val = act_row.get(col, "")
            match, detail = _values_match(exp_val, act_val, col)
            if not match:
                mismatches.append(f"Row {i + 1}: {detail}")

    passed = len(mismatches) == 0
    result = {
        "pass": passed,
        "query": query_num,
        "expected_rows": len(expected_rows),
        "actual_rows": len(actual_rows),
        "mismatches": mismatches,
        "missing_rows": max(0, len(expected_rows) - len(actual_rows)),
        "extra_rows": max(0, len(actual_rows) - len(expected_rows)),
    }

    if verbose:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"Q{query_num}: {status}")
        print(f"  Expected rows: {len(expected_rows)}, Actual rows: {len(actual_rows)}")
        if mismatches:
            for m in mismatches[:20]:
                print(f"  {m}")
            if len(mismatches) > 20:
                print(f"  ... and {len(mismatches) - 20} more mismatches")

    return result


def check_all_queries(
    walker_results: dict[int, Any],
    answers_dir: str,
    verbose: bool = True,
) -> dict[str, Any]:
    """Verify all walker results at once.

    Args:
        walker_results: Dict mapping query number (1–22) to walker result.
        answers_dir: Path to the answers directory.
        verbose: Print per-query results.

    Returns:
        A summary dict with keys:
            "total": int — number of queries checked
            "passed": int — number that matched
            "failed": int — number that didn't match
            "results": dict[int, dict] — per-query result dicts
    """
    results: dict[int, dict[str, Any]] = {}
    passed = 0
    failed = 0

    for q_num in sorted(walker_results.keys()):
        result = check_query(q_num, walker_results[q_num], answers_dir, verbose=verbose)
        results[q_num] = result
        if result["pass"]:
            passed += 1
        else:
            failed += 1

    total = passed + failed
    if verbose:
        print(f"\n{'=' * 50}")
        print(f"Summary: {passed}/{total} queries passed, {failed} failed")
        print(f"{'=' * 50}")

    return {
        "total": total,
        "passed": passed,
        "failed": failed,
        "results": results,
    }
