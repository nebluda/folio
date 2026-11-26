#!/usr/bin/env python3
"""Time the installed Folio extension through a macOS Quick Look preview view."""
import argparse
import json
import math
import pathlib
import plistlib
import statistics
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def build_probe(directory):
    contents = directory / 'QLProbe.app/Contents'
    binary = contents / 'MacOS/QLProbe'
    binary.parent.mkdir(parents=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'io.github.nebluda.folio.quick-look-probe',
        'CFBundleExecutable': 'QLProbe',
        'CFBundleName': 'Folio Quick Look Benchmark',
        'CFBundlePackageType': 'APPL',
    }))
    subprocess.run(['swiftc', ROOT / 'Tools/FolioQuickLookBench/main.swift', '-O', '-o', binary], check=True)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', default=20, type=int)
    parser.add_argument('--output', default=ROOT / 'build/quick-look-performance.json', type=pathlib.Path)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error('--trials must be positive')
    scenarios = {
        'first_100KB': [], 'next_small': [], 'next_100KB': [],
        'next_1MB': [], 'next_1MB_varied': [],
    }
    with tempfile.TemporaryDirectory(prefix='folio-quick-look-') as temp:
        directory = pathlib.Path(temp)
        probe = build_probe(directory)
        subprocess.run(['swift', 'run', '-c', 'release', 'FolioBench', '--fixtures-only', directory],
                       cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        small = (ROOT / 'Fixtures/Welcome.md').read_text(encoding='utf-8')
        medium = (directory / '100000.md').read_text(encoding='utf-8')
        large = (directory / '1000000.md').read_text(encoding='utf-8')
        varied = ''.join(
            f'## Section {index}{part.replace("greeting", f"greeting{index}")}'
            for index, part in enumerate(large.split('## A readable section')[1:], 1)
        )
        for trial in range(args.trials):
            command = [probe]
            for index, source in enumerate([medium, small, medium, large, varied]):
                heading = f'Folio benchmark heading {trial}-{index}'
                path = directory / f'{trial}-{index}.md'
                path.write_text(f'## {heading}\n\n{source}', encoding='utf-8')
                command.extend([path, heading])
            lines = subprocess.check_output(command, text=True, timeout=80).splitlines()
            values = [float(line) for line in lines]
            if len(values) != len(scenarios):
                raise RuntimeError('The Quick Look probe returned an unexpected number of timings')
            for samples, value in zip(scenarios.values(), values):
                samples.append(value)

    report = {}
    for scenario, samples in scenarios.items():
        ordered = sorted(samples)
        report[scenario] = {
            'median_ms': round(statistics.median(samples), 1),
            'p95_ms': round(ordered[math.ceil(.95 * len(ordered)) - 1], 1),
            'runs_ms': [round(value, 1) for value in samples],
        }
        print(f"{scenario:<17} median {report[scenario]['median_ms']:>7.1f} ms / p95 {report[scenario]['p95_ms']:>7.1f} ms")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
