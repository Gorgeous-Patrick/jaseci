"""Read-only confirmation that the previous Transformer example is unchanged."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
snapshot = json.loads((root / 'preservation.json').read_text())
old = (root / snapshot['directory']).resolve()
actual = {str(path.relative_to(old)): hashlib.sha256(path.read_bytes()).hexdigest()
          for path in old.rglob('*') if path.is_file() and '__pycache__' not in path.parts}
assert actual == snapshot['sha256'], 'Previous transformer_graph files changed'
print(f'PASS: all {len(actual)} previous Transformer files unchanged (SHA-256)')
