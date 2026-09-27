#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d build/Folio.app ]]; then python3 scripts/package.py; fi
app_dir="${FOLIO_INSTALL_DIR:-$HOME/Applications}"
bin_dir="${FOLIO_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$app_dir" "$bin_dir"
# ditto preserves signatures and replaces the app as one staged installation.
staged_app="$app_dir/.Folio.installing.app"
if [[ -e "$staged_app" ]]; then rm -rf "$staged_app"; fi
ditto build/Folio.app "$staged_app"
if [[ -e "$app_dir/Folio.app" ]]; then
    /usr/bin/osascript -e 'tell application id "io.github.nebluda.folio" to quit' || true
    rm -rf "$app_dir/Folio.app"
fi
mv "$staged_app" "$app_dir/Folio.app"
ln -sfn "$app_dir/Folio.app/Contents/MacOS/folio" "$bin_dir/folio"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir/Folio.app"
pluginkit -a "$app_dir/Folio.app/Contents/PlugIns/FolioPreview.appex"
pluginkit -e use -i io.github.nebluda.folio.preview
printf 'Installed %s\nCLI: %s/folio\n' "$app_dir/Folio.app" "$bin_dir"
printf 'If needed, add %s to PATH. See README for Finder defaults.\n' "$bin_dir"
