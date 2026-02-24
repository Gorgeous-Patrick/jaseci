"""TTG Performance Benchmark Fixture.

Measures the time taken by TTG generation (get_ttg) and prefetch list
construction (get_prefetch_list) across graphs of increasing size.

Outputs timing data in a structured format for comparison:
  BENCH <label> <time_ms>

Graph sizes: 50, 100, 200, 500 nodes with mixed types and edges.
Each size is measured multiple times and the median is reported.
"""

import os;
import time;
import from statistics { median }
import from uuid { UUID, uuid4 }
import from jaclang.jac0core.ttg { JacTTGGenerator, TypedWalkerState }
import from jaclang.jac0core.archetype { VisitType }

# ── Edge types ────────────────────────────────────────────────────────────────
edge HttpEdge {}
edge DbEdge {}
edge CacheEdge {}

# ── Node types ────────────────────────────────────────────────────────────────
node Server {
    has name: str;
}

node Database {
    has name: str;
}

node Cache {
    has name: str;
}

# ── Walker with all edge types from all node types ────────────────────────────
walker FullCrawler {
    has visited: list[str] = [];

    can enter_root with Root entry {
        visit [->:HttpEdge:->];
    }

    can visit_server with Server entry {
        self.visited.append(here.name);
        visit [->:HttpEdge:->];
        visit [->:DbEdge:->];
    }

    can visit_db with Database entry {
        self.visited.append(here.name);
        visit [->:DbEdge:->];
        visit [->:CacheEdge:->];
    }

    can visit_cache with Cache entry {
        self.visited.append(here.name);
        visit [->:CacheEdge:->];
        visit [->:HttpEdge:->];
    }
}

# ── Walker with selective edges (HttpEdge + DbEdge only) ─────────────────────
walker SelectiveCrawler {
    has visited: list[str] = [];

    can enter_root with Root entry {
        visit [->:HttpEdge:->];
    }

    can visit_server with Server entry {
        self.visited.append(here.name);
        visit [->:HttpEdge:->];
        visit [->:DbEdge:->];
    }

    can visit_db with Database entry {
        self.visited.append(here.name);
        visit [->:DbEdge:->];
    }
}

# ── Synthetic graph builder ──────────────────────────────────────────────────
"""Build a synthetic graph with N nodes (excluding root) and mixed types/edges.

Returns (graph, type_map, root_id) suitable for direct JacTTGGenerator calls.
The graph has a chain topology with branches:
  - Every 3rd node gets a DbEdge branch to a Database node
  - Every Database node gets a CacheEdge branch to a Cache node
  - Main chain uses HttpEdge connecting Server nodes
"""
def build_synthetic_graph(n_servers: int) -> tuple {
    graph: list[tuple[(UUID, UUID, UUID)]] = [];
    type_map: dict[(UUID, type)] = {};

    root_id = uuid4();
    type_map[root_id] = type(None);  # Root placeholder

    # Build server chain
    servers: list[UUID] = [];
    for i in range(n_servers) {
        sid = uuid4();
        type_map[sid] = Server;
        servers.append(sid);
    }

    # Connect root -> first server
    if servers {
        eid = uuid4();
        type_map[eid] = HttpEdge;
        graph.append((root_id, eid, servers[0]));
    }

    # Server chain: s0 -> s1 -> ... -> sN
    for i in range(len(servers) - 1) {
        eid = uuid4();
        type_map[eid] = HttpEdge;
        graph.append((servers[i], eid, servers[i + 1]));
    }

    # Every 3rd server gets a Database branch
    databases: list[UUID] = [];
    for i in range(0, len(servers), 3) {
        did = uuid4();
        type_map[did] = Database;
        databases.append(did);
        eid = uuid4();
        type_map[eid] = DbEdge;
        graph.append((servers[i], eid, did));
    }

    # Database chain where consecutive DBs are connected
    for i in range(len(databases) - 1) {
        eid = uuid4();
        type_map[eid] = DbEdge;
        graph.append((databases[i], eid, databases[i + 1]));
    }

    # Each database gets a Cache branch
    caches: list[UUID] = [];
    for i in range(len(databases)) {
        cid = uuid4();
        type_map[cid] = Cache;
        caches.append(cid);
        eid = uuid4();
        type_map[eid] = CacheEdge;
        graph.append((databases[i], eid, cid));
    }

    # Some caches connect back to servers (cross-layer, no cycles since new servers)
    extra_servers: list[UUID] = [];
    for i in range(0, len(caches), 2) {
        sid = uuid4();
        type_map[sid] = Server;
        extra_servers.append(sid);
        eid = uuid4();
        type_map[eid] = HttpEdge;
        graph.append((caches[i], eid, sid));
    }

    total_nodes = 1 + len(servers) + len(databases) + len(caches) + len(extra_servers);
    return (graph, type_map, root_id, total_nodes);
}

"""Run a benchmark for a given graph size. Returns dict of timing results."""
def benchmark_size(n_servers: int, iterations: int = 5) -> dict {
    (graph, type_map, root_id, total_nodes) = build_synthetic_graph(n_servers);

    # Create walker instances with __jac_ttg_visits__
    full_walker = FullCrawler();
    selective_walker = SelectiveCrawler();

    # ── Benchmark get_ttg with FullCrawler ────────────────────────────────
    ttg_full_times: list[float] = [];
    for _ in range(iterations) {
        t0 = time.perf_counter();
        (ttg_state, visited, child_map) = JacTTGGenerator.get_ttg(
            full_walker, root_id, graph, type_map
        );
        t1 = time.perf_counter();
        ttg_full_times.append((t1 - t0) * 1000);  # ms
    }

    # ── Benchmark get_ttg with SelectiveCrawler ───────────────────────────
    ttg_sel_times: list[float] = [];
    for _ in range(iterations) {
        t0 = time.perf_counter();
        (ttg_state2, visited2, child_map2) = JacTTGGenerator.get_ttg(
            selective_walker, root_id, graph, type_map
        );
        t1 = time.perf_counter();
        ttg_sel_times.append((t1 - t0) * 1000);
    }

    # ── Benchmark get_prefetch_list ───────────────────────────────────────
    prefetch_times: list[float] = [];
    for _ in range(iterations) {
        t0 = time.perf_counter();
        prefetch_list = JacTTGGenerator.get_prefetch_list(root_id, child_map);
        t1 = time.perf_counter();
        prefetch_times.append((t1 - t0) * 1000);
    }

    return {
        "total_nodes": total_nodes,
        "graph_edges": len(graph),
        "type_map_entries": len(type_map),
        "ttg_full_median_ms": round(median(ttg_full_times), 4),
        "ttg_sel_median_ms": round(median(ttg_sel_times), 4),
        "prefetch_median_ms": round(median(prefetch_times), 4),
        "ttg_full_visited": len(visited),
        "ttg_sel_visited": len(visited2),
        "prefetch_count": len(prefetch_list)
    };
}

# ── Run benchmarks across multiple sizes ─────────────────────────────────────
with entry {
    sizes = [50, 100, 200, 500];
    iterations = 7;

    print("=== TTG Performance Benchmark ===");
    print(f"Iterations per size: {iterations} (median reported)");
    print("");

    for sz in sizes {
        result = benchmark_size(sz, iterations);
        print(f"--- Graph: {sz} servers, {result['total_nodes']} total nodes, {result['graph_edges']} edges ---");
        print(f"BENCH get_ttg_full_{sz} {result['ttg_full_median_ms']}");
        print(f"BENCH get_ttg_selective_{sz} {result['ttg_sel_median_ms']}");
        print(f"BENCH get_prefetch_{sz} {result['prefetch_median_ms']}");
        print(f"  full_visited={result['ttg_full_visited']} sel_visited={result['ttg_sel_visited']} prefetch_count={result['prefetch_count']}");
        print("");
    }

    print("=== Benchmark Complete ===");
}
