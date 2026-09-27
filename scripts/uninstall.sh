#!/bin/bash
set -euo pipefail
app_dir="${FOLIO_INSTALL_DIR:-$HOME/Applications}"
bin_dir="${FOLIO_BIN_DIR:-$HOME/.local/bin}"
if pgrep -x Folio >/dev/null; then echo 'Quit Folio before uninstalling.' >&2; exit 1; fi
if [[ -d "$app_dir/Folio.app" ]]; then
    pluginkit -r "$app_dir/Folio.app/Contents/PlugIns/FolioPreview.appex" || true
    rm -rf "$app_dir/Folio.app"
fi
if [[ -e "$bin_dir/folio" || -L "$bin_dir/folio" ]]; then
    if [[ -L "$bin_dir/folio" ]] || [[ "$("$bin_dir/folio" --version)" == Folio* ]]; then rm "$bin_dir/folio"; fi
fi
printf 'Folio removed. Your Markdown files were not changed.\n'
