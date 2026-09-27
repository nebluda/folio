#!/usr/bin/env python3
"""Build a relocatable app + Quick Look extension using Apple's command-line tools."""
import pathlib, plistlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
configuration = 'debug' if '--debug' in sys.argv else 'release'
subprocess.run(['swift', 'build', '-c', configuration], cwd=ROOT, check=True)
binaries = pathlib.Path(subprocess.check_output(['swift', 'build', '-c', configuration, '--show-bin-path'], cwd=ROOT, text=True).strip())
app = ROOT / 'build/Folio.app'
if app.exists(): shutil.rmtree(app)
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True)
(contents / 'Resources').mkdir()
shutil.copy2(binaries / 'Folio', contents / 'MacOS/Folio')
(contents / 'Helpers').mkdir()
shutil.copy2(binaries / 'FolioCLI', contents / 'Helpers/folio')
shutil.copytree(binaries / 'Folio_FolioCore.bundle', contents / 'Resources/Folio_FolioCore.bundle')
shutil.copy2(ROOT / 'App/Info.plist', contents / 'Info.plist')
icon = ROOT / 'App/Folio.icns'
if icon.exists(): shutil.copy2(icon, contents / 'Resources/Folio.icns')
extension = contents / 'PlugIns/FolioPreview.appex/Contents'
(extension / 'MacOS').mkdir(parents=True)
(extension / 'Resources').mkdir()
shutil.copy2(binaries / 'FolioPreview', extension / 'MacOS/FolioPreview')
shutil.copy2(ROOT / 'Extension/Info.plist', extension / 'Info.plist')
shutil.copytree(binaries / 'Folio_FolioCore.bundle', extension / 'Resources/Folio_FolioCore.bundle')
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(ROOT / 'Extension/FolioPreview.entitlements'), str(extension.parent)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(contents / 'Helpers/folio')], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app)
