# GPU named-cursor layout experiment archive - 2026-10-06

Recovered raw evidence from the RTX 3090 experiment. The original 717 files are
preserved without content changes. This README was added during recovery.

- [Results and evidence limits](../../docs/design/gpu-cursor-layout-results.md)
- [Input configuration, environment and source hashes](inputs.json)
- [Summary](summary.json), [wall/event timing samples](wall-events.csv)
- [Controlled normal timing](controlled-normal/records.csv) and
  [controlled profiler timing](controlled-profile/records.csv)
- [Layout identity audit](identity-audit/layout-identity-audit.json)
- [CPU profiles](cpu-profile/cpu-profile.json)
- [Nsight report](trace.nsys-rep), [SQLite export](trace.sqlite), and
  [aligned kernel launches](profile-launches.csv)
- [CUDA regression log](jac-named-exclusive-cuda.log) and
  [host regression log](jac-named-final-host.log)
- [Exact measured source snapshot](source-snapshot/)
- [Original SHA-256 manifest](artifact-sha256.json): 716 entries, excluding itself.

Per-case directories retain typed input arrays and layout permutations. The
identity audit retains reconstructed arrays and identity orders. Log and JSON
paths mentioning `/tmp/jac-layout-exclusive` or the old home directory describe
the original run; resolve them within this archive when inspecting saved files.
The live `compare_named_layouts.py` additionally records identity order metadata;
`source-snapshot/` preserves the version that produced the measurements.

The measurements show no consistent predicted-layout kernel improvement for the
tested shared-input matmul cases. Nsight Compute hardware counters were blocked
by permissions; cache/coalescing/occupancy explanations remain unverified. See
the results report for the exact scope and comparison conditions.

Verify the recovered evidence from the repository root:

```bash
python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path("dist/gpu-layout-exclusive-20261006")
manifest = json.loads((root / "artifact-sha256.json").read_text())
for name, expected in manifest.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name
print(f"Verified {len(manifest)} archived files")
PY
```
