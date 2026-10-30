# TTG: Dependency-Guided Prefetching in Jac

[Open the English PDF](ttg-dependency-prefetch.pdf).

The 27-slide deck explains the mechanism through a persisted A/B/C/D graph and
actual Jac source. It uses white backgrounds, black sans-serif text, vector
diagrams and limited accent colors. Source code uses a monospaced font.

## Flow

| Slides | Content |
| --- | --- |
| 1-4 | Research problem, persisted graph, actual Jac abilities |
| 5-8 | Shared walker state, dependency edges, definition merges, compiler/runtime split |
| 9-13 | Automatic hooks, queue-prefix checks, FIFO semantics, overwrites, three certificate properties |
| 14-21 | Visit lowering, SQL, worker/cache pipeline, overlap, deduplication, budgets, batches, savepoints, metrics |
| 22-25 | Current integration validation, historical adapter measurements, DB-call accounting |
| 26-27 | Cost-admission research direction, configuration and reproduction |

The implementation shown is commit `9b1ac5ff9`. The source listings use the exact test-fixture snapshot in
[data/fixture-source.txt](data/fixture-source.txt), extracted from that commit.
Its SHA256 is recorded with the current validation data.

## Build

Install a TeX distribution with `pdflatex`, TikZ/PGF, listings, Helvetica,
Courier, sansmath, geometry, booktabs and amssymb. From this directory:

```sh
make
```

The output is `ttg-dependency-prefetch.pdf`. Intermediate files are kept in the
ignored `build/` directory. `make clean` removes those intermediates.

## Evidence

- [Current validation summary](data/current-validation.json): nine new integration
  cases, 85 targeted runtime tests, 11 static and format/lint checks. The counts
  describe assertions in PostgreSQL-backed tests and real raw-cache promotions.
- [Validation procedure](../../design/ttg-dependencies/validation.md).
- [Mechanism and API](../../design/ttg-dependencies/README.md).
- [Historical trial records](data/historical-adapter-trials.csv): the 33 original
  trials selected for slide 23.
- [Complete primary cohort](data/historical-adapter-full-trials.csv) and
  [six-setting matrix](data/historical-adapter-matrix.csv): all 264 trials and
  their paired-policy setting medians, shown on slide 24.
- [Historical medians](data/historical-adapter-summary.csv) and
  [provenance](data/provenance.json): filter, aggregation, source-file SHA256,
  workload setup and measurement boundaries.

The historical measurements use an explicit prediction adapter from 27 October:
16 payload nodes per branch, 16 KiB per node, B already loaded, a warmed main
connection, and an active transaction. The displayed setting uses configured RTT
5 ms and a 20 ms independent I/O-wait model, with 11 trials per policy.

The automatic-hook implementation introduces savepoint control commands and a
different execution path. Its latency and DB-call measurements are a subsequent
evaluation stage. The deck labels these two evidence sources separately.

## Presentation conventions

- Put the project name on the first slide.
- Explain the research problem, give a concrete example, introduce the solution,
  revisit that example through the mechanism, then present evidence.
- Use as many slides as the mechanism needs; keep individual diagrams readable.
- Label illustrative timelines and preserve precise metric boundaries.
- State results directly. Use positive scope descriptions and evidence-backed
  claims.
