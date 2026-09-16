# Sources and claim boundaries

## Primary research references

1. **Milind Kulkarni, Keshav Pingali, Bruce Walter, Ganesh Ramanarayanan, Kavita Bala, and L. Paul Chew.** “Optimistic Parallelism Requires Abstractions.” *PLDI*, 2007, pp. 211–222. [Author-hosted paper](https://www.cs.cornell.edu/~kb/publications/Galois_PLDI07.pdf). DOI: 10.1145/1250734.1250759.

   Relevant precedent: Galois uses abstractions and runtime conflict detection to parallelize irregular applications. It demonstrates that OOP systems can also expose semantic contracts. Used in appendix A.

2. **Maurice Herlihy and Eric Koskinen.** “Transactional Boosting: A Methodology for Highly-Concurrent Transactional Objects.” *PPoPP*, 2008, pp. 207–216. [Author-hosted paper](https://erickoskinen.com/papers/boosting-ppopp08.pdf). DOI: 10.1145/1345206.1345237.

   Relevant precedent: abstract object operations, commutativity, and inverses can support transactional objects. Additional context for appendix A.

3. **Michael Bauer, Sean Treichler, Elliott Slaughter, and Alex Aiken.** “Legion: Expressing Locality and Independence with Logical Regions.” *SC*, 2012. [Author-hosted paper](https://theory.stanford.edu/~aiken/publications/papers/sc12.pdf). DOI: 10.1109/SC.2012.71.

   Relevant precedent: logical regions, access privileges, and coherence properties expose information for task scheduling and locality. Used in appendix A.

4. **Joel Saltz, Harry Berryman, and Janet Wu.** “Multiprocessors and run-time compilation.” *Concurrency: Practice and Experience*, 3(6), 1991, pp. 573–592. [Publisher page](https://onlinelibrary.wiley.com/doi/abs/10.1002/cpe.4330030607). DOI: 10.1002/cpe.4330030607.

   Relevant precedent: runtime preprocessing can support parallel execution and can be integrated into compilers. Used in appendix A to position the proposal near inspector–executor methods: inspect the access structure first, then execute the work. This reference does not establish the specific Jac mechanism or its performance.

These references establish relevant precedent; this is not an exhaustive novelty review. The candidate contribution and experimental hypotheses in slides 1–8 are this proposal's reasoning, rather than results established by the cited papers.

## Current implementation

- [PR #9215](https://github.com/jaseci-labs/jac/pull/9215).
- Source snapshot inspected: `3c3a7ffb2eaafb1083219dde9a9fb7583c301346`.
- [Current commit-time validation](https://github.com/Gorgeous-Patrick/jaseci/blob/3c3a7ffb2eaafb1083219dde9a9fb7583c301346/jac/jaclang/runtime/walker_speculation_native.jac#L398).
- [Graph-query runtime](https://github.com/Gorgeous-Patrick/jaseci/blob/3c3a7ffb2eaafb1083219dde9a9fb7583c301346/jac/jaclang/runtime/osp_graph.jac#L302).
- [Native speculation instrumentation](https://github.com/Gorgeous-Patrick/jaseci/blob/3c3a7ffb2eaafb1083219dde9a9fb7583c301346/jac/jaclang/compiler/backends/native/walker_speculation.jac).

The implemented baseline is opt-in native walker speculation with memory-access tracking, ordered validation/commit, and serial fallback. Compiler-generated pre-execution query inspectors, conservative read/write summaries, inspection invalidation, and dependency-aware task admission are proposed extensions. They are not implemented or evaluated by the referenced prototype.

## Proposed mechanism

1. Extract safe graph queries and conservative read/write summaries from an ability. A query result alone does not identify possible writers.
2. For a concrete queued call, bind its known starting node, walker, and arguments. Run the separate inspection function before launching the body to find actual node identities and the graph data used by the lookup.
3. Compare queued calls in their original serial order. Delay a later call when its possible reads or writes conflict with an earlier call. Independent calls may compute together; effects still publish in the original order.
4. If an earlier update changes inputs used by inspection, re-inspect the affected calls and rebuild their dependencies before launch. Returning no nodes does not remove the dependency on the searched edges and filter inputs.
5. Keep ordinary speculative tracking and validation initially. Queries whose inputs depend on unavailable body results, own mutations, or unknown effectful calls retain conservative handling or the existing fallback. Newly created calls are inspected once known.

This does not require splitting the ability body into computation and side-effect phases. It does require a sound, side-effect-free inspector for the subset of accesses evaluated early. Inspection may be conservative, may duplicate work done in the body, and may need to be repeated. Reduced retries alone do not establish an end-to-end improvement.

The current prototype waits for a speculative batch to finish before ordered commits. Launching dependent calls after earlier commits therefore requires changing task admission and commit coordination, or using successive ready batches; it is not supplied merely by adding query metadata.

## Benchmark provenance

Appendix B uses the previously collected measurements bundled as [prototype_benchmark.json](prototype_benchmark.json), originally stored in `/tmp/jac-walker-speedup.json` during development. No performance experiment was rerun for this deck.

- 16 independent jobs; 6.4 million floating-point steps per job.
- Native AOT, reference counting, optimization level 2, host libc.
- Linux host reporting 16 logical CPUs; local toolchain compatibility setup documented in the PR.
- Two warm-ups and seven timed runs per mode; median wall time shown.
- Serial/off: 423.828 ms; two threads: 341.169 ms; four threads: 222.953 ms.
- Four-thread speedup: 1.90098×; 16 commits; zero fallbacks; matching output.

This is a synthetic, conflict-free CPU kernel. It supplies a baseline feasibility result. The proposed pre-execution inspection and scheduling scheme has no measured speedup yet.

## Correctness obligations for the proposal

- Inspection must use a coherent graph view. Validation and dependency registration must prevent changes from slipping between the inspection check and task admission; retain final validation for unproven accesses.
- Track possible read/write targets and the graph data determining query membership and order. Obtaining a reference is not itself a read of every field; whole-node summaries are a conservative starting approximation based on subsequent use.
- Include liveness, subtype/direction matching, and predicate reads, including rejected candidates where relevant.
- Every corresponding write must participate, including writes through aliases and calls, graph mutations, and writes that change a query predicate's inputs.
- Refresh both readers' and writers' target summaries if earlier updates invalidate their inspection inputs. Rebuild dependencies after refresh.
- Preserve read-after-write, write-after-read, and write-after-write ordering. A writer that follows a reader in the serial program must not be moved before it.
- Node-granularity tracking is conservative. Non-node heap state, shared containers, and effects outside the proven coverage retain existing instrumentation or serial fallback.
- Only safe, available inputs may be evaluated early. Conditional accesses can be overapproximated; evaluating arbitrary predicates or body prefixes speculatively is not assumed safe inspection.
- Compare concrete known calls; do not assume the complete future traversal is available in advance.
- Preserve the original serial order of commits and observable walker effects. Use eager memory conflict detection as a comparison, and include inspection, re-inspection, scheduler overhead, and unnecessary waiting in the evaluation.
