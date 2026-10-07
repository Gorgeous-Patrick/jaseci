"""Generate readable views from the ACTUAL exported analysis, not an architecture drawing."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('analysis', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = json.loads(args.analysis.read_text())
    output = args.output or args.analysis.parent
    output.mkdir(exist_ok=True, parents=True)
    for prefix, label in [('dec_attn', 'attention'), ('enc_norm1', 'norm')]:
        selected = {name for name in report['order'] if name.startswith(prefix + '.') or name == prefix}
        # Include actual boundary producers, retaining port labels and inferred metadata.
        edges = [edge for edge in report['edges'] if edge[1] in selected]
        selected.update(edge[0] for edge in edges)
        lines = ['digraph DataflowView {', 'rankdir=LR;']
        for name in report['order']:
            if name in selected:
                spec = report['specs'][name]
                node_label = f"{name}\n{report['node_types'][name]}\n{spec['shape']} / {spec['dtype']}"
                lines.append(f'{json.dumps(name)} [label={json.dumps(node_label)}];')
        for producer, consumer, port in edges:
            lines.append(f'{json.dumps(producer)} -> {json.dumps(consumer)} [label={json.dumps(port)}];')
        lines.append('}')
        path = output / (label + '.dot')
        path.write_text('\n'.join(lines) + '\n')
        print(path)

if __name__ == '__main__':
    main()
