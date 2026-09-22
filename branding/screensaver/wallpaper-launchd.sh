#!/bin/zsh
set -euo pipefail
usage() { print -u2 "usage: $0 enable|disable [wallpaper-app-path]"; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
SCRIPT_DIR="${0:A:h}"
action="$1"
label="com.richard.omac.wallpaper"
agent_dir="$HOME/Library/LaunchAgents"
plist="$agent_dir/$label.plist"
app_path="${2:-/Applications/Omac.app/Contents/Resources/Extras/OMAC-Wallpaper.app}"
binary="$app_path/Contents/MacOS/OMAC-Wallpaper"
case "$action" in
  enable)
    [[ -x "$binary" ]] || { print -u2 "Wallpaper app is not executable: $binary"; exit 1; }
    mkdir -p "$agent_dir"
    launchctl disable "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    /usr/bin/python3 - "$plist" "$binary" <<'PY'
import plistlib
import sys

plist_path, binary_path = sys.argv[1:]
with open(plist_path, "wb") as stream:
    plistlib.dump({
        "Label": "com.richard.omac.wallpaper",
        "ProgramArguments": [binary_path],
        "RunAtLoad": True,
        "ProcessType": "Background",
    }, stream, fmt=plistlib.FMT_XML, sort_keys=False)
PY
    launchctl enable "gui/$(id -u)/$label"
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl kickstart -k "gui/$(id -u)/$label"
    ;;
  disable)
    launchctl disable "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    rm -f "$plist"
    ;;
  *) usage ;;
esac
