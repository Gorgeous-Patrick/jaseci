# Resolve Dependencies Before Abilities Run

An English research-proposal deck for a PhD advisor: **8 main slides + 2 optional appendices**, intended for a 10–15 minute conversation.

## Open the presentation

- **jac_dependency_idea.pdf** — shareable presentation, with embedded fonts and linked references.
- **jac_dependency_idea.pptx** — editable PowerPoint; diagrams use native shapes and text. Speaker notes are embedded.
- **speaker_notes.md** — the full presentation narrative and qualifications, by slide.
- **slide_overview.png** — a visual overview of all ten slides.
- **sources.md** — bibliography, source links, benchmark provenance, and claim boundaries.

The core argument is: the compiler can generate a small inspection function from eligible graph queries and read/write summaries. Before launching an ability body, the scheduler runs that function on the current graph, identifies overlapping accesses among queued calls, and delays calls that depend on earlier work. If inspection inputs change, it refreshes the dependencies. This may avoid wasted speculative computation while preserving serial behavior. The deck keeps this proposal separate from the implemented prototype and its existing synthetic benchmark.

The running examples use explicit nodes and values: A changes a score from 10 to 20; B must calculate using 20. A separate three-call example shows why A and an independent C can compute together while B waits. Query inspection happens before the ability body starts. Existing speculative validation handles accesses that have not been proven safe by inspection.

The proposed scope includes multi-hop queries. A query is eligible when its inputs can be obtained safely before the body starts; hop count is not a support boundary. Inspection tracks the graph data examined at intermediate hops as well as the final access targets.

The PDF has been rendered and visually inspected. The PowerPoint uses the same layout primitives, with Arial and Consolas font names for portability; use the PDF for fixed layout across computers.

## Rebuild

Run `python build_slides.py` with standard CPython and these packages:

```text
python-pptx==1.0.2
reportlab==5.0.1
pymupdf==1.28.2
Pillow==12.3.0
```

The script discovers Liberation Sans and DejaVu Sans Mono with `fc-match` for PDF font embedding. Keep `prototype_benchmark.json` next to the script. The JSON contains the original measurements, and the script calculates the displayed values from it.
