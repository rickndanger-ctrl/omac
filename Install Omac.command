#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
source_app="$source_dir/Omac.app"
target_app="/Applications/Omac.app"
stamp="$(date +%Y%m%d-%H%M%S)"

if pgrep -f "$target_app/Contents/MacOS/AgentControlCenter" >/dev/null 2>&1; then
  print -u2 'Omac is running. Close it and retry; the installer will not replace a live app.'
  exit 1
fi
[[ -d "$source_app" ]] || { print -u2 "Missing $source_app"; exit 1; }

if [[ -e "$target_app" ]]; then
  backup="$target_app.backup.$stamp"
  mv "$target_app" "$backup"
  print "Existing Omac moved to $backup"
fi
ditto "$source_app" "$target_app"

saver_source="$target_app/Contents/Resources/Extras/OMAC.saver"
saver_dir="$HOME/Library/Screen Savers"
mkdir -p "$saver_dir"
if [[ -e "$saver_dir/OMAC.saver" ]]; then
  mv "$saver_dir/OMAC.saver" "$saver_dir/OMAC.saver.backup.$stamp"
fi
ditto "$saver_source" "$saver_dir/OMAC.saver"

state="$HOME/Library/Application Support/AgentControlCenter"
mkdir -p "$state"
if [[ ! -e "$state/wallpaper.selected" ]]; then
  print -n 'storm-forge' > "$state/wallpaper.selected"
fi
"$target_app/Contents/MacOS/AgentControlCenter" --prepare-runtime
"$target_app/Contents/MacOS/AgentControlCenter" --check

if [[ "${OMAC_NO_LAUNCH:-1}" == 0 ]]; then
  open -a "$target_app"
fi
print 'Omac installed. Login startup remains off until enabled from the Omac menu.'
