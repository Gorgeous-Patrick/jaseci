# JacYac load testing

Locust scenarios for JacYac's authenticated walker API. Provision a separate
identity for every concurrent user, seed posts and follow edges, then measure
the existing sessions. Registration and proof-of-work run before the timed test.

## Quick start

Use Python 3.12+ (a standard GIL build), and run these commands from this directory:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
mkdir -p results
```

In another terminal, start a **dedicated test instance** from the JacYac workspace
root (`jac/examples/jaclang_org`). Use an isolated workspace/database for disposable
data. `--no-client` skips the frontend build while retaining the web API routes:

```bash
jac run --no-client --host 127.0.0.1 --port 8000 web
```

Then provision five users, one post each, three follows each, and a channel:

```bash
.venv/bin/python seed.py --host http://127.0.0.1:8000 --users 5
.venv/bin/locust -f locustfile.py --headless \
  --host http://127.0.0.1:8000 --accounts local.accounts.json \
  --users 5 --spawn-rate 1 --run-time 1m --stop-timeout 60 \
  --reset-stats --csv results/smoke --csv-full-history --html results/smoke.html
```

For the interactive UI, omit `--headless`, `--users`, `--spawn-rate`, and
`--run-time`; open `http://localhost:8089`. Keep the requested user count at or
below the account count.

The default route is `/api/social_graph/walker/<name>` for the `web` app, both
colocated and behind the fleet gateway. To test the social service directly:

```bash
jac run --no-client --host 127.0.0.1 --port 8000 social_graph
```

Pass `--walker-prefix /walker` to **both** `seed.py` and Locust in that case.
Direct service measurements exclude the web/gateway hop. Use the same topology,
database backend, worker count, resource limits, and dataset for comparisons.

## Workload

Each user verifies its token and nonempty feed at startup. Account exhaustion,
expired credentials, and a missing profile stop the run. Concurrent users never
share an account. Default think time is 1–3 seconds between tasks.

| Task | Browsing | With `--write-workload` |
|---|---:|---:|
| `load_feed` | 50% | 40% |
| `get_all_profiles` | 15% | 15% |
| `get_profile` | 10% | 10% |
| `get_channels` | 10% | 10% |
| `get_trending` | 10% | 10% |
| `load_feed(search_query="jac")` | 5% | 5% |
| Create post → like → comment → delete own post | 0% | 10% |

These are **task selection weights**, not request ratios. A write transaction
immediately calls `load_feed` after each successful create, like, comment, and
delete, including a successful retry of a pending deletion. A fully successful
transaction therefore issues eight requests: four writes and four feed refreshes.
These refreshes count in the same `load_feed` statistics row as ordinary browsing;
they have no think-time delay. Failed writes do not trigger a refresh. Shutdown
cleanup only deletes any remaining test posts.

The transaction waits for its posting slot. When the slot is not ready, the task
reads the feed instead. The default write interval is 10.1 seconds
because posts and comments share a quota. Test posts are deleted in the transaction,
with a final cleanup attempt when a user stops; interrupted requests or failed
cleanup can leave posts behind. Keep the test database disposable. Fixture posts,
accounts, follows, and the channel remain for subsequent runs.

```bash
.venv/bin/locust -f locustfile.py --headless \
  --host http://127.0.0.1:8000 --accounts local.accounts.json \
  --users 5 --spawn-rate 1 --run-time 2m --stop-timeout 60 \
  --write-workload --reset-stats \
  --csv results/mixed --csv-full-history --html results/mixed.html
```

HTTP errors, redirects, malformed JSON, failed transport envelopes, empty walker
reports, `ok: false`, and `PostingDenied` all count as failures. Empty **lists inside
a report** are valid; the seeded feed is additionally checked at startup. Error
labels and request names remain stable so statistics do not split by token, node
ID, or dynamic rate-limit messages. Feed reads and searches share the `load_feed`
statistics row.

The test covers HTTP API performance. It does not measure rendering, JavaScript,
static asset loading, GitHub OAuth, repository downloads/scoring, or AI latency.
Those require separate scenarios; the current workload makes no third-party calls.

## Preparing a larger fixture

The app currently permits 5 registration attempts per IP per hour, 20 registration
challenges per IP per 10 minutes, 1 post/comment per user per 10 seconds, and 50
posts/comments per user per day. Existing counters also apply to later seed/test
runs. A posting denial may arrive inside an HTTP 200 response.

For a larger fixture, change these settings **in the dedicated test workspace's
existing `[serve.auth]` section**, then restart that server:

```toml
registration_attempts_per_hour = 2000
registration_challenges_per_10_minutes = 2000
```

Keep `registration_challenge = true`; the seeder solves the real challenge. For
large datasets or sustained writes, choose explicit test-server limits through
`JACYAC_POSTS_PER_WINDOW`, `JACYAC_POST_WINDOW_SECONDS`, and
`JACYAC_POSTS_PER_DAY`. For example, `JACYAC_POSTS_PER_WINDOW=100000
JACYAC_POSTS_PER_DAY=100000 jac run ...` permits capacity testing; pass
`--post-interval 0` to the seeder/Locust only for that configuration. Record these
overrides alongside results. A rate-limit test should retain the normal limits.

```bash
# After setting test-server limits, prepare 200 identities and 4,000 posts.
.venv/bin/python seed.py --host http://127.0.0.1:8000 \
  --accounts capacity.accounts.json --users 200 \
  --posts-per-user 20 --follows-per-user 10 --post-interval 0
```

`--resume` continues from the saved accounts after a provisioning failure, fills
missing posts, and avoids duplicate follow edges. It does not refresh expired
tokens. To refresh credentials or change dataset shape, start with a fresh test
database and a new account file. Generated passwords are discarded; tokens are
saved with file mode `0600`. `*.accounts.json` and `results/` are gitignored.
Provisioned accounts are bound to the exact host and route prefix to catch
accidental fixture/target mismatches.

With the normal server limits, the default five-user fixture can be created
without configuration changes, provided those registration quotas are unused.
Increasing the number of virtual users alone does not model a larger graph:
`load_feed` traverses the user's/followed profiles' posts, and `get_trending`
traverses tweets across roots. Vary graph size separately from concurrency.

## Capacity runs and acceptance

Start with the smoke run, then increase concurrency in separate runs. For example,
with a 200-account fixture, run 10, 50, 100, then 200 users for 5 minutes each:

```bash
for users in 10 50 100 200; do
  .venv/bin/locust -f locustfile.py --headless \
    --host http://127.0.0.1:8000 --accounts capacity.accounts.json \
    --users "$users" --spawn-rate 5 --run-time 5m --stop-timeout 60 \
    --reset-stats --max-failure-ratio 0.01 --max-p95-ms 1000 \
    --csv "results/read-$users" --csv-full-history \
    --html "results/read-$users.html" || break
done
```

Run a 30-minute soak at the highest passing level. For writes, check that the daily
posting allowance covers the whole run. `--run-time` includes ramp-up; `--reset-stats`
clears statistics after all users have spawned, but is not a fixed warm-up period.
Allow time for startup/cache warm-up before recording the capacity run.

Default exit gates are at least 100 requests, at most 1% failures, and aggregate
p95 at most 1,000 ms. These are initial test targets, not an established JacYac SLO.
Override with `--min-requests`, `--max-failure-ratio`, and `--max-p95-ms`.
Exit code 0 means the configured gates passed; 1 means sample/performance gates
or user-code execution failed; 2 means fixture/configuration setup failed. Small
smoke tests may lower `--min-requests`, but should not be used to estimate capacity.

Compare per-endpoint RPS, p50/p95/p99 and failure counts in the CSV/HTML report
alongside server CPU/RSS, database connections/latency/locks, and gateway/worker
errors. Record commit, fixture counts, limits, topology and resources with each
report. A local load generator sharing the server's CPU gives a functional
baseline; use a separate machine for a capacity claim. Concurrent users are not
equal to RPS because response time and think time both affect throughput.

This version uses one Locust process. It rejects `--master`/`--worker`/multi-process
mode to prevent duplicated account pools. Watch load-generator CPU before
interpreting a throughput plateau; distributed execution needs disjoint account
allocation and coordinated failure reporting first.

## Script checks

```bash
.venv/bin/python -m unittest discover -p 'test_*.py' -v
.venv/bin/locust -f locustfile.py --list
```

References: [Locust tasks and response validation](https://docs.locust.io/en/stable/writing-a-locustfile.html),
[headless runs and exit codes](https://docs.locust.io/en/stable/running-without-web-ui.html).
