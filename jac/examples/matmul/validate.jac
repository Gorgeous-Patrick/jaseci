"""Execute every matmul implementation on CPU and check independent oracles."""

import argparse;
import copy;
import hashlib;
import decimal;
import json;
import math;
import random;
import time;
import sys;
import importlib;
import from pathlib { Path }
import from catalog { implementations }
import from common { dimensions }
import dense;
import recursive;
import graphs;

obj Case {
    has name: str,
        a: list[list[float]],
        b: list[list[float]],
        exact: bool;
}

def cases -> list[Case] {
    rng = random.Random(20261002);
    result = [
        Case(
            "known",
            [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]],
            [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]],
            True
        ),
        Case("negative_singleton", [[-2.0]], [[3.0]], True),
        Case(
            "zeros", [[0.0] * 3 for i in range(2)], [[1.0] * 4 for i in range(3)], True
        ),
        Case("identity", [[1.0, 0.0], [0.0, 1.0]], [[-3.0, 2.0], [4.0, -5.0]], True),
        Case("signed_zero", [[-0.0, 0.0]], [[2.0], [-3.0]], True),
        Case("cancellation", [[100000.0, 1.0, -100000.0]], [[1.0], [1.0], [1.0]], True)
    ];
    for (m, kk, n) in (
        (1, 9, 7),
        (7, 1, 6),
        (3, 5, 4),
        (5, 3, 7),
        (8, 8, 8),
        (9, 7, 5)
    ) {
        a = [[float(rng.randrange(-9, 10)) for k in range(kk)] for i in range(m)];
        b = [[float(rng.randrange(-9, 10)) for j in range(n)] for k in range(kk)];
        result.append(Case(f"integer_{m}_{kk}_{n}", a, b, True));
    }
    for (m, kk, n) in ((2, 3, 4), (3, 7, 5), (5, 5, 5), (8, 8, 8), (9, 7, 5)) {
        a = [[rng.uniform(-2.0, 2.0) for k in range(kk)] for i in range(m)];
        b = [[rng.uniform(-2.0, 2.0) for j in range(n)] for k in range(kk)];
        result.append(Case(f"float_{m}_{kk}_{n}", a, b, False));
    }
    a = [
        [0.0 if rng.random() < 0.8 else rng.uniform(-2, 2) for k in range(7)]
        for i in range(5)
    ];
    b = [
        [0.0 if rng.random() < 0.8 else rng.uniform(-2, 2) for j in range(6)]
        for k in range(7)
    ];
    result.append(Case("sparse_float", a, b, False));
    result.append(
        Case(
            "diagonal",
            [[2.0, 0.0, 0.0], [0.0, -3.0, 0.0], [0.0, 0.0, 4.0]],
            [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]],
            True
        )
    );
    return result;
}

def oracle(case_data: Case) -> list[list[float]] {
    (m, kk, n) = dimensions(case_data.a, case_data.b);
    if case_data.exact {
        return [
            [
                float(
                    sum(
                        int(case_data.a[i][k]) * int(case_data.b[k][j])
                        for k in range(kk)
                    )
                ) for j in range(n)
            ] for i in range(m)
        ];
    }
    with decimal.localcontext() as ctx {
        ctx.prec = 100;
        return [
            [
                float(
                    sum(
                        (
                            decimal.Decimal.from_float(case_data.a[i][k])
                                * decimal.Decimal.from_float(case_data.b[k][j])
                            for k in range(kk)
                        ),
                        decimal.Decimal(0)
                    )
                ) for j in range(n)
            ] for i in range(m)
        ];
    }
}

def check(
    actual: list[list[float]], expected: list[list[float]], exact: bool, label: str
) -> float {
    assert len(actual) == len(expected) , f"{label}: output row count";
    error = 0.0;
    for (row, ref) in zip(actual, expected) {
        assert len(row) == len(ref) , f"{label}: output column count";
        for (value, wanted) in zip(row, ref) {
            assert math.isfinite(value) , f"{label}: nonfinite output";
            valid = value == wanted
                if exact
                else math.isclose(value, wanted, rel_tol=1e-10, abs_tol=1e-10);
            assert valid , f"{label}: {value} != {wanted}";
            error = max(error, abs(value - wanted));
        }
    }
    return error;
}

with entry {
    parser = argparse.ArgumentParser(
        description="Validate Jac matmul implementations on CPU"
    );
    parser.add_argument(
        "--no-libraries", action="store_true", help="Use only Jac and standard library"
    );
    parser.add_argument(
        "--json", help="Write a machine-readable verification summary_data"
    );
    args = parser.parse_args();
    variants = implementations(include_libraries=not args.no_libraries);
    examples = cases();
    references = [oracle(case_data) for case_data in examples];
    invalid = [
        ([], [[1.0]]),
        ([[]], [[1.0]]),
        ([[1.0]], []),
        ([[1.0, 2.0]], [[1.0]]),
        ([[1.0], [2.0, 3.0]], [[1.0]]),
        ([[1.0, 2.0]], [[1.0], []])
    ];
    records: list[dict[str, any]] = [];
    for implementation in variants {
        elapsed = 0.0;
        error = 0.0;
        for (case_data, expected) in zip(examples, references) {
            saved = copy.deepcopy((case_data.a, case_data.b));
            begin = time.perf_counter();
            actual = implementation.function(case_data.a, case_data.b);
            elapsed += (time.perf_counter() - begin) * 1000;
            error = max(
                error,
                check(
                    actual,
                    expected,
                    case_data.exact,
                    implementation.name + "/" + case_data.name
                )
            );
            assert (case_data.a, case_data.b) == saved , f"{implementation.name} mutated inputs";
        }
        for (a, b) in invalid {
            rejected = False;
            try {
                implementation.function(a, b);
            } except ValueError {
                rejected = True;
            }
            assert rejected , f"{implementation.name}: invalid shape accepted";
        }
        records.append(
            {
                "name": implementation.name,
                "family": implementation.family,
                "cases_passed": len(examples),
                "invalid_shapes_rejected": len(invalid),
                "max_absolute_error": error,
                "elapsed_ms": elapsed
            }
        );
        print(
            f"PASS {implementation.name:22} cases={len(examples)} max_error={error:.3g}"
        );
    }
    # Independently known answer, visible without reading the oracle code.
    for implementation in variants {
        assert implementation.function(examples[0].a, examples[0].b)
            == [[58.0, 64.0], [139.0, 154.0]];
    }
    configuration_checks = 0;
    configurations: list[tuple[str, any]] = [
        ("blocked", dense.blocked),
        ("packed_tiles", dense.packed_tiles),
        ("split_k", dense.split_k),
        ("strassen", recursive.strassen),
        ("strassen_winograd", recursive.strassen_winograd),
        ("output_tile_tasks", graphs.output_tile_tasks)
    ];
    for (name, function) in configurations {
        for setting in (1, 2, 3, 8, 32) {
            for index in (0, 8, 17) {
                case_data = examples[index];
                actual = function(case_data.a, case_data.b, setting);
                check(
                    actual,
                    references[index],
                    case_data.exact,
                    f"{name}/{setting}/{case_data.name}"
                );
                configuration_checks += 1;
            }
        }
        for setting in (0, -1) {
            rejected = False;
            try {
                function(examples[0].a, examples[0].b, setting);
            } except ValueError {
                rejected = True;
            }
            assert rejected , f"{name}: nonpositive configuration accepted";
        }
    }
    source_dir = Path(__file__).resolve().parent;
    source_hashes = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(source_dir.glob("*.jac"))
    };
    versions: dict[str, str] = {};
    if not args.no_libraries {
        for name in ("numpy", "scipy") {
            if importlib.util.find_spec(name) is not None {
                versions[name] = importlib.import_module(name).__version__;
            }
        }
    }
    summary_data = {
        "cpu_executed": True,
        "gpu_executed": False,
        "python_version": sys.version,
        "backend": "Jac Python CPU",
        "random_seed": 20261002,
        "library_versions": versions,
        "source_sha256": source_hashes,
        "configuration_checks": configuration_checks,
        "implementation_count": len(variants),
        "case_count": len(examples),
        "exact_case_count": sum(int(case_data.exact) for case_data in examples),
        "float_rel_tol": 1e-10,
        "float_abs_tol": 1e-10,
        "cases": [
            {
                "name": case_data.name,
                "shape": list(dimensions(case_data.a, case_data.b)),
                "exact": case_data.exact
            } for case_data in examples
        ],
        "implementations": records
    };
    if args.json {
        destination = Path(args.json);
        destination.parent.mkdir(parents=True, exist_ok=True);
        destination.write_text(json.dumps(summary_data, indent=2) + "\n");
    }
    print("Known result: [[58.0, 64.0], [139.0, 154.0]]");
    print(
        f"PASS: {len(variants)} CPU implementations, {len(
            examples
        )} cases each, all outputs agree"
    );
}
