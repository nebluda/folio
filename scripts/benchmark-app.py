#!/usr/bin/env python3
"""Measure process-start / CLI-open to WKWebView navigation completion on generated files.
Quit Folio first. This opens temporary test windows, then terminates only its own process.
"""
import json, os, pathlib, shutil, statistics, subprocess, time
root = pathlib.Path(__file__).resolve().parents[1]
app = pathlib.Path(os.environ.get('FOLIO_APP_PATH', str(pathlib.Path.home() / 'Applications/Folio.app')))
cli = pathlib.Path.home() / '.local/bin/folio'
fixtures = root / 'build/bench-fixtures'
log = root / 'build/app-performance.csv'
if subprocess.run(['pgrep', '-x', 'Folio'], capture_output=True).returncode == 0:
    raise SystemExit('Quit Folio before running this benchmark.')
subprocess.run(['swift', 'run', '-c', 'release', 'FolioBench', str(fixtures)], cwd=root, check=True, stdout=subprocess.DEVNULL)
def wait_for_lines(count):
    deadline = time.time() + 30
    while time.time() < deadline:
        lines = log.read_text().splitlines()
        if len(lines) >= count: return float(lines[count-1].split(',')[0])
        time.sleep(.01)
    raise TimeoutError('No completed render within 30 seconds')
results = {'cold_100KB_ms': [], 'warm_100KB_ms': [], 'warm_1MB_ms': []}
for trial in range(3):
    log.write_text('')
    start = time.time()
    process = subprocess.Popen([str(app / 'Contents/MacOS/Folio'), str(fixtures / '100000.md')], env=dict(os.environ, FOLIO_PERF_LOG=str(log)), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        results['cold_100KB_ms'].append((wait_for_lines(1) - start) * 1000)
        for index, size in enumerate([100000, 1000000], start=2):
            path = fixtures / f'open-{trial}-{size}.md'
            shutil.copyfile(fixtures / f'{size}.md', path)
            start = time.time()
            subprocess.run([str(cli), str(path)], env=dict(os.environ, FOLIO_APP_PATH=str(app)), check=True, timeout=10)
            key = 'warm_100KB_ms' if size == 100000 else 'warm_1MB_ms'
            results[key].append((wait_for_lines(index) - start) * 1000)
    finally:
        process.terminate()
        process.wait(timeout=10)
report = {key: {'median_ms': round(statistics.median(values), 1), 'runs_ms': [round(x, 1) for x in values]} for key, values in results.items()}
print(json.dumps(report, indent=2))
(root / 'build/app-performance.json').write_text(json.dumps(report, indent=2) + '\n')
