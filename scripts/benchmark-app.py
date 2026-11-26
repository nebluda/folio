#!/usr/bin/env python3
"""Measure opening a new Markdown window through WebKit navigation completion."""
import argparse
import json
import math
import os
import pathlib
import platform
import statistics
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCENARIOS = (
    ('cold_100KB', '100000.md'),
    ('warm_small', 'small.md'),
    ('warm_100KB', '100000.md'),
    ('warm_1MB', '1000000.md'),
    ('warm_1MB_varied', 'varied.md'),
)


def wait_for_render(log, index, process):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        lines = log.read_text().splitlines(keepends=True)
        if len(lines) > index and lines[index].endswith('\n'):
            # Older builds supply the timestamp and preview duration only.
            return list(map(float, lines[index].split(',')))
        if process.poll() is not None:
            raise RuntimeError(f'Folio exited before completing render {index + 1}')
        time.sleep(.01)
    raise TimeoutError(f'No completed render {index + 1} within 30 seconds')


def run_trial(app, fixtures):
    with tempfile.TemporaryDirectory(prefix='folio-bench-') as directory:
        directory = pathlib.Path(directory)
        log = directory / 'performance.csv'
        log.touch()
        env = dict(os.environ, FOLIO_PERF_LOG=str(log), FOLIO_APP_PATH=str(app))
        files = []
        for scenario, fixture in SCENARIOS:
            path = directory / f'{scenario}.md'
            path.write_bytes((fixtures / fixture).read_bytes())
            files.append(path)
        start = time.time()
        # Suppress AppKit window restoration. A restored document can finish
        # rendering before the requested fixture and spoil the measurement.
        process = subprocess.Popen([app / 'Contents/MacOS/Folio', '-ApplePersistenceIgnoreState', 'YES',
                                    '-NSQuitAlwaysKeepsWindows', 'NO', files[0]], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for index, ((scenario, _), path) in enumerate(zip(SCENARIOS, files)):
                if index:
                    start = time.time()
                    subprocess.run([app / 'Contents/Helpers/folio', path], env=env, check=True, timeout=20)
                timestamp, *stages = wait_for_render(log, index, process)
                opened = (timestamp - start) * 1000
                if not stages or not 0 <= stages[0] <= opened:
                    raise RuntimeError(f'{scenario}: logged preview started before the open request')
                if len(stages) == 4 and stages[3] != path.stat().st_size:
                    raise RuntimeError(f'{scenario}: logged document size does not match the fixture')
                times = {'open_ms': opened}
                times.update(zip(('preview_ms', 'html_ms', 'webkit_ms'), stages[:3]))
                yield scenario, times
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def summarize(values):
    ordered = sorted(values)
    return {
        'median': round(statistics.median(ordered), 1),
        'p95': round(ordered[math.ceil(.95 * len(ordered)) - 1], 1),
        'runs': [round(value, 1) for value in values],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default_app = os.environ.get('FOLIO_APP_PATH', ROOT / 'build/Folio.app')
    parser.add_argument('--app', type=pathlib.Path, default=default_app)
    parser.add_argument('--baseline', type=pathlib.Path, help='Alternate trial order with a reference bundle')
    parser.add_argument('--trials', type=int, default=20)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'build/app-performance.json')
    args = parser.parse_args()
    if args.trials < 1:
        parser.error('--trials must be positive')
    if subprocess.run(['pgrep', '-x', 'Folio'], capture_output=True).returncode == 0:
        parser.error('Quit Folio before running this benchmark.')
    apps = {'app': args.app.resolve()}
    if args.baseline:
        apps['baseline'] = args.baseline.resolve()
    for app in apps.values():
        if not all((app / path).is_file() for path in ('Contents/MacOS/Folio', 'Contents/Helpers/folio')):
            parser.error(f'Missing Folio app or CLI at {app}')
    with tempfile.TemporaryDirectory(prefix='folio-fixtures-') as directory:
        fixtures = pathlib.Path(directory)
        subprocess.run(['swift', 'run', '-c', 'release', 'FolioBench', '--fixtures-only', fixtures],
                       cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        (fixtures / 'small.md').write_bytes((ROOT / 'Fixtures/Welcome.md').read_bytes())
        source = (fixtures / '1000000.md').read_text(encoding='utf-8')
        # Keep the same block mix but vary headings and code to exercise cache misses.
        sections = source.split('## A readable section')
        varied = ''.join(
            f'## Section {index}{section.replace("greeting", f"greeting{index}")}'
            for index, section in enumerate(sections[1:], 1)
        )
        (fixtures / 'varied.md').write_text(varied, encoding='utf-8')
        sizes = {name: (fixtures / name).stat().st_size for _, name in SCENARIOS}
        samples = {label: {name: {} for name, _ in SCENARIOS} for label in apps}
        for trial in range(args.trials):
            order = list(apps) if trial % 2 == 0 else list(reversed(apps))
            for label in order:
                for scenario, times in run_trial(apps[label], fixtures):
                    for metric, value in times.items():
                        samples[label][scenario].setdefault(metric, []).append(value)
    report = {
        'trials': args.trials,
        'machine': {'macos': platform.mac_ver()[0],
                    'cpu': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()},
        'fixture_bytes': sizes,
        'results': {
            label: {scenario: {metric: summarize(values) for metric, values in timings.items()}
                    for scenario, timings in scenarios.items()}
            for label, scenarios in samples.items()
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    for label, scenarios in report['results'].items():
        print(f'{label} ({apps[label]})')
        for name, timings in scenarios.items():
            opened = timings['open_ms']
            print(f"  {name:<17} median {opened['median']:>7.1f} ms / p95 {opened['p95']:>7.1f} ms")
    print(f'Results: {args.output}')


if __name__ == '__main__':
    main()
