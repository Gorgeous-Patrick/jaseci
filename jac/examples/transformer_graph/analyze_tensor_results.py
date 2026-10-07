"""Aggregate saved measurements; never run inference or reinterpret profiler as latency."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def main():
    summary = {'notes': ['End-to-end samples are unprofiled.',
                         'Profiler sums/window/gaps are separate observations, not a latency decomposition.',
                         'First compile calls used an existing persistent Inductor cache.'], 'cases': []}
    lines = ['| device | config | dtype | Jac median / p90 ms | eager median / p90 ms | compile median / p90 ms |',
             '|---|---|---|---:|---:|---:|']
    for device in ('cpu', 'cuda'):
        data = json.loads((ROOT / 'results' / f'benchmark_{device}.json').read_text())
        for case in data['cases']:
            row = {'device': device, 'config': case['config_name'], 'dtype': case['dtype'],
                   'initialization': case['initialization'], 'graphs': {}}
            for name, graph in case['graphs'].items():
                profiles = {}
                for method, profile in graph['profiles'].items():
                    calls = profile['calls']
                    profiles[method] = {key: profile[key] for key in
                        ('calls', 'cuda_kernel_count', 'kernel_sum_ms', 'kernel_window_ms',
                         'kernel_window_minus_busy_ms', 'launch_count', 'launch_cpu_ms',
                         'cpu_exclusive_categories_ms', 'trace_file')}
                    profiles[method]['kernel_count_per_request'] = profile['cuda_kernel_count'] / calls
                    profiles[method]['kernel_sum_per_request_ms'] = profile['kernel_sum_ms'] / calls
                row['graphs'][name] = {
                    'timings': {method: {key: value for key, value in metrics.items() if key != 'warmup_total_ms'}
                                for method, metrics in graph['methods'].items()},
                    'scheduler_replay': graph['scheduler_replay'], 'profiles': profiles,
                    'compile': graph['compile'], 'max_intermediate_error': graph['max_intermediate_error'],
                    'probability_delta': graph['probability_delta_from_original_graph']}
            if device == 'cuda':
                row['peak_allocated_bytes'] = case['max_cuda_allocated_bytes']
                row['peak_reserved_bytes'] = case['max_cuda_reserved_bytes']
            summary['cases'].append(row)
            metrics = case['graphs']['original']['methods']
            cells = [f"{metrics[m]['end_to_end']['median_ms']:.4f} / {metrics[m]['end_to_end']['p90_ms']:.4f}"
                     for m in ('jac_graph', 'torch_eager', 'torch_compile')]
            lines.append('| ' + ' | '.join([device, case['config_name'], case['dtype'], *cells]) + ' |')
    (ROOT / 'results' / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (ROOT / 'results' / 'timing_table.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    for row in summary['cases']:
        original = row['graphs']['original']
        print(row['device'], row['config'], row['dtype'], 'replay median ms',
              original['scheduler_replay']['end_to_end']['median_ms'],
              'compile first ms', original['compile']['first_call_compile_and_execution_ms'],
              'peak MiB', row.get('peak_allocated_bytes', 0) / 2**20)

if __name__ == '__main__':
    main()
