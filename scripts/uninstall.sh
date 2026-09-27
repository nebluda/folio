#!/bin/bash
set -euo pipefail
app_dir="${FOLIO_INSTALL_DIR:-$HOME/Applications}"
bin_dir="${FOLIO_BIN_DIR:-$HOME/.local/bin}"
/usr/bin/osascript -e 'tell application id "io.github.nebluda.folio" to quit' || true
if [[ -d "$app_dir/Folio.app" ]]; then
    pluginkit -r "$app_dir/Folio.app/Contents/PlugIns/FolioPreview.appex" || true
    rm -rf "$app_dir/Folio.app"
fi
if [[ -L "$bin_dir/folio" ]]; then rm "$bin_dir/folio"; fi
printf 'Folio removed. Your Markdown files were not changed.\n'
