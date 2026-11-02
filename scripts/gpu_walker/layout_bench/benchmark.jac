"""Plan or explicitly run the documented Jac GPU layout experiment."""
import argparse;
import from datetime { datetime, timezone }
import hashlib;
import importlib.util;
import jaclang;
import json;
import os;
import from pathlib { Path }
import shlex;
import shutil;
import subprocess;
import sys;
glob HERE: Path = Path(__file__).resolve().parent,
     ROOT: Path = HERE.parents[2],
     WALKERS: Path = HERE.parent,
     STUDY: Path = WALKERS / 'layout_study',
     MATMUL: Path = WALKERS / 'handwritten_matmul',
     SHAPES: tuple[str, ...] = (
         '3x5x2',
         '17x31x19',
         '64x128x64',
         '128x128x128',
         '256x256x256'
     );

def sha(path: any) -> str {
    digest = hashlib.sha256();
    with Path(path).open('rb') as stream {
        for block in iter(lambda() { stream.read((1024 * 1024)); }, b'') {
            digest.update(block);
        }
    }
    return digest.hexdigest();
}

def write_json(path: any, data: any) {
    Path(path).write_text((json.dumps(data, indent=2) + '\n'));
}

"""Pure command construction: no tool discovery, imports, writes, or launches."""
def steps(
    output: any,
    *,
    python: str = sys.executable,
    nvcc: str = 'nvcc',
    ptxas: str = 'ptxas',
    nsys: str = 'nsys',
    ncu: str = 'ncu'
) -> list[tuple[str, list[str]]] {
    output = Path(output).resolve();
    inputs = output / 'inputs/inputs.json';
    codegen = output / 'optimized-codegen';
    validation = codegen / 'status-validation.json';
    profile = output / 'optimized-profile';
    def py(script: any, *args: any) -> list[str] {
        return [python, '-B', str(script)] + [str(arg) for arg in args];
    }
    def replay(folder: any, warmup: int, repeats: int) -> list[str] {
        return py(
            (STUDY / 'run.py'),
            '--inputs',
            inputs,
            '--jac-ptx',
            (codegen / 'O2.ptx'),
            '--status-evidence',
            validation,
            '--output',
            folder,
            '--nvcc',
            nvcc,
            '--warmup',
            warmup,
            '--repeats',
            repeats,
            '--inner',
            16,
            '--order-seed',
            237
        );
    }
    return [
        (
            'prepare-production',
            py(
                (MATMUL / 'prepare_inputs.py'),
                '--output',
                (output / 'production-inputs'),
                '--shapes',
                *SHAPES
            )
        ),
        (
            'audit-layouts',
            py(
                (STUDY / 'prepare.py'),
                '--source',
                (output / 'production-inputs/inputs.json'),
                '--output',
                inputs.parent
            )
        ),
        (
            'compile-checked-o2',
            py(
                (STUDY / 'emit_checked_o2.py'),
                '--inputs',
                inputs,
                '--output',
                codegen,
                '--fresh-validation',
                '--ptxas',
                ptxas
            )
        ),
        (
            'validate-gpu-statuses',
            py(
                (MATMUL / 'validate_codegen.py'),
                '--codegen',
                codegen,
                '--output',
                validation,
                '--variants',
                'baseline',
                'O2'
            )
        ),
        (
            'profile',
            [
                str(nsys),
                'profile',
                '--trace=cuda',
                '--cuda-graph-trace=node',
                '--sample=none',
                '--cpuctxsw=none',
                '--output',
                str((profile / 'trace')),
                *replay(profile, 3, 15)
            ]
        ),
        (
            'export-trace',
            [
                str(nsys),
                'export',
                '--type',
                'sqlite',
                '--output',
                str((profile / 'trace.sqlite')),
                str((profile / 'trace.nsys-rep'))
            ]
        ),
        (
            'audit-trace',
            py(
                (STUDY / 'analyze.py'),
                (profile / 'results.json'),
                (profile / 'trace.sqlite'),
                '--output',
                (profile / 'verified.json')
            )
        ),
        ('ordinary-events', replay((output / 'optimized-ordinary'), 5, 25)),
        (
            'address-model',
            py(
                (STUDY / 'address_analysis.py'),
                '--inputs',
                inputs,
                '--profile',
                (profile / 'results.json'),
                '--output',
                (output / 'optimized-address-analysis.json')
            )
        ),
        (
            'counter-probe',
            py(
                (STUDY / 'counter_probe.py'),
                output,
                '--ncu',
                ncu,
                '--nvcc',
                nvcc,
                '--status-evidence',
                validation
            )
        ),
        (
            'report',
            [
                str(python),
                '-B',
                '-m',
                'jaclang',
                'run',
                '--backend',
                'python',
                str(HERE / 'results.jac'),
                str(output)
            ]
        )
    ];
}

def source_hashes -> dict[str, str] {
    paths = `set();
    for directory in [STUDY, MATMUL, HERE] {
        paths.update(directory.glob('*.py'));
        paths.update(directory.glob('*.jac'));
        paths.update(directory.glob('*.cu'));
    }
    for directory in [
        (ROOT / 'jac/jaclang/compiler'),
        (ROOT / 'jac/jaclang/runtime')
    ] {
        for pattern in ('*.py', '*.jac') {
            paths.update(directory.rglob(pattern));
        }
    }
    paths.update(WALKERS.glob('*.py'));
    paths.update(
        [
            (STUDY / 'RESEARCH_CONTRACT.md'),
            (HERE / 'SPEC.md'),
            (ROOT / 'jac/examples/gpu/named_cursors.jac')
        ]
    );
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(paths)};
}

def run_suite(args: any) {
    if (sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE')) {
        raise ValueError(
            'Use Python without -O or PYTHONOPTIMIZE: existing validation requires assertions.'
        );
    }
    output = args.output.resolve();
    if output.exists() {
        raise ValueError(
            f'Refusing to overwrite an existing output directory: {output}'
        );
    }
    compiler_package = Path(jaclang.__file__).resolve().parent;
    if (compiler_package != (ROOT / 'jac/jaclang').resolve()) {
        raise ValueError(
            f'Loaded Jac compiler is {compiler_package}; execution requires this checkout. Enable its jac.toml dev source and install its typeshed stubs.'
        );
    }
    if ((sys.platform != 'linux') or (sys.byteorder != 'little')) {
        raise ValueError(
            'Execution requires little-endian Linux and a CUDA GPU; plan works without them.'
        );
    }
    for module in ['numpy', 'matplotlib'] {
        if (importlib.util.find_spec(module) is None) {
            raise ValueError(
                f'Missing {module} in {sys.executable}; see README.md prerequisites.'
            );
        }
    }
    tools = {};
    for name in ['nvcc', 'ptxas', 'nsys'] {
        tools[name] = shutil.which(getattr(args, name));
        if (tools[name] is None) {
            raise ValueError(f'Executable not found: {getattr(args, name)}');
        }
    }
    if (shutil.which('nvidia-smi') is None) {
        raise ValueError('nvidia-smi must be available for device snapshots.');
    }
    tools['ncu'] = shutil.which(args.ncu) or args.ncu;
    commands = steps(output, **tools);
    env = os.environ.copy();
    env['PYTHONPATH'] = os.pathsep.join([str((ROOT / 'jac')), str(WALKERS)]);
    env['PYTHONDONTWRITEBYTECODE'] = '1';
    env['MPLBACKEND'] = 'Agg';
    output.mkdir(parents=True, exist_ok=False);
    (output / 'logs').mkdir();
    (output / 'optimized-profile').mkdir();
    env['MPLCONFIGDIR'] = str((output / 'matplotlib-cache'));
    record: dict[str, any] = {
        'status': 'running',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'python': sys.version,
        'python_executable': sys.executable,
        'compiler_package': str(compiler_package),
        'repository': str(ROOT),
        'output': str(output),
        'source_sha256': source_hashes(),
        'stages': [],
        'versions': {}
    };
    write_json((output / 'commands.json'), record);
    try {
        for (label, command) in [
            ('git_revision', ['git', 'rev-parse', 'HEAD']),
            ('git_status', ['git', 'status', '--short']),
            ('nvcc', [tools['nvcc'], '--version']),
            ('ptxas', [tools['ptxas'], '--version']),
            ('nsys', [tools['nsys'], '--version']),
            ('nvidia_smi', ['nvidia-smi'])
        ] {
            record['versions'][label] = subprocess.check_output(
                command, cwd=ROOT, env=env, text=True, stderr=subprocess.STDOUT
            );
        }
        for (name, command) in commands {
            print(f'[{name}] {shlex.join(command)}', flush=True);
            stage: dict[str, any] = {
                'name': name,
                'command': command,
                'status': 'running',
                'log': f'logs/{name}.log'
            };
            record['stages'].append(stage);
            write_json((output / 'commands.json'), record);
            with (output / stage['log']).open('w') as log {
                result = subprocess.run(
                    command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT
                );
            }
            stage['exit_code'] = result.returncode;
            stage['status'] = 'complete' if (result.returncode == 0) else 'failed';
            stage['log_sha256'] = sha((output / stage['log']));
            write_json((output / 'commands.json'), record);
            if result.returncode {
                raise RuntimeError(f'{name} failed; see {(output / stage["log"])}');
            }
        }
        record['status'] = 'complete';
    } except BaseException as error {
        record['status'] = 'failed';
        record['error'] = str(error);
        raise;
    } finally {
        record['finished_utc'] = datetime.now(timezone.utc).isoformat();
        write_json((output / 'commands.json'), record);
    }
}

def main(argv: list[str] | None = None) -> None {
    parser = argparse.ArgumentParser(description=__doc__);
    parser.add_argument(
        'action',
        choices=['plan', 'run'],
        help='plan has no execution side effects; run executes GPU work'
    );
    parser.add_argument(
        '--output',
        `type=Path,
        required=True,
        help='A fresh directory for all new evidence'
    );
    for name in ['nvcc', 'ptxas', 'nsys', 'ncu'] {
        parser.add_argument(
            ('--' + name),
            `default=name,
            help=f'{name} executable, resolved on PATH by run'
        );
    }
    args = parser.parse_args(argv);
    if (args.action == 'plan') {
        print(
            'PLAN ONLY: no result files created, no GPU compilation, execution or measurements.'
        );
        for (name, command) in steps(
            args.output,
            **{k: getattr(args, k) for k in ['nvcc', 'ptxas', 'nsys', 'ncu']}
        ) {
            print(f'[{name}] {shlex.join(command)}');
        }
        return;
    }
    try {
        run_suite(args);
    } except (
        ValueError,
        RuntimeError,
        OSError,
        subprocess.CalledProcessError
    ) as error {
        parser.exit(1, f'Error: {error}\n');
    }
}

with entry:__main__ {
    main();
}
