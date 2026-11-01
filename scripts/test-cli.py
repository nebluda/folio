#!/usr/bin/env python3
"""Exercise the actual CLI process without modifying user documents."""
import os, pathlib, plistlib, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
cli = root / 'build/Folio.app/Contents/Helpers/folio'
def run(*args, env=None):
    return subprocess.run([str(cli), *args], capture_output=True, text=True, timeout=10, env=env)
with (root / 'build/Folio.app/Contents/Info.plist').open('rb') as file:
    version = plistlib.load(file)['CFBundleShortVersionString']
assert run('--version').stdout.strip() == f'Folio {version}'
assert 'Usage:' in run('--help').stdout
for args in [('--unknown',), ('missing.md',), (str(root),)]:
    result = run(*args)
    assert result.returncode == 1 and result.stderr.startswith('folio:'), result
result = run(str(root / 'Fixtures/Welcome.md'), env=dict(os.environ, FOLIO_APP_PATH='/nonexistent/Folio.app'))
assert result.returncode == 1 and 'not installed' in result.stderr
print('6 CLI process checks passed')
