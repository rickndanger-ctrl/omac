#!/bin/zsh
# Install only after preflight; preserve a reversible backup and never stop terminals.
set -euo pipefail
source_dir="${0:A:h}"
source_app="$source_dir/Omac.app"
target_app="${OMAC_INSTALL_DESTINATION:-/Applications/Omac.app}"
state="${OMAC_STATE_ROOT:-$HOME/Library/Application Support/AgentControlCenter}"
saver_dir="${OMAC_SAVER_DESTINATION:-$HOME/Library/Screen Savers}"
backup_root="${OMAC_BACKUP_ROOT:-$HOME/Library/Application Support/Omac/InstallerBackups}"
stamp="$(date +%Y%m%d-%H%M%S)-$$"
backup="$backup_root/$stamp"

[[ -d "$source_app" ]] || { print -u2 "Missing $source_app"; exit 1; }
if pgrep -f "$target_app/Contents/MacOS/AgentControlCenter" >/dev/null 2>&1; then
 print -u2 'Choose Disengage Omac, then Quit Omac before installing. Your terminal sessions can stay open.'
 exit 1
fi
if [[ -e "$state/aerospace.enabled" ]]; then
 print -u2 'Omac window management is still enabled. Disengage it before installing.'
 exit 1
fi
# Check the downloaded copy before moving any existing installation or user data.
codesign --verify --deep --strict "$source_app"
"$source_app/Contents/MacOS/AgentControlCenter" --check
[[ -d "$source_app/Contents/Resources/Extras/OMAC.saver" ]] || { print -u2 'Screensaver missing from package.'; exit 1; }
mkdir -p "${target_app:h}" "$backup" "$saver_dir"
app_existed=0; state_existed=0; saver_existed=0; mutation_started=0
[[ ! -e "$target_app" ]] || { ditto "$target_app" "$backup/Omac.app"; app_existed=1; }
[[ ! -e "$state" ]] || { ditto "$state" "$backup/state"; state_existed=1; }
[[ ! -e "$saver_dir/OMAC.saver" ]] || { ditto "$saver_dir/OMAC.saver" "$backup/OMAC.saver"; saver_existed=1; }
rollback() {
 local result=$?
 if (( result != 0 && mutation_started )); then
  # Keep the failed installation for diagnosis; restore the original paths.
  [[ ! -e "$target_app" ]] || mv "$target_app" "$backup/failed-Omac.app"
  [[ ! -e "$state" ]] || mv "$state" "$backup/failed-state"
  [[ ! -e "$saver_dir/OMAC.saver" ]] || mv "$saver_dir/OMAC.saver" "$backup/failed-OMAC.saver"
  (( ! app_existed )) || ditto "$backup/Omac.app" "$target_app"
  (( ! state_existed )) || ditto "$backup/state" "$state"
  (( ! saver_existed )) || ditto "$backup/OMAC.saver" "$saver_dir/OMAC.saver"
  print -u2 "Installation failed; original files restored. Diagnostic backup: $backup"
 fi
}
trap rollback EXIT
mutation_started=1
[[ ! -e "$target_app" ]] || mv "$target_app" "$backup/replaced-Omac.app"
ditto "$source_app" "$target_app"
[[ ! -e "$saver_dir/OMAC.saver" ]] || mv "$saver_dir/OMAC.saver" "$backup/replaced-OMAC.saver"
ditto "$target_app/Contents/Resources/Extras/OMAC.saver" "$saver_dir/OMAC.saver"
mkdir -p "$state"
[[ -e "$state/wallpaper.selected" ]] || print -n 'storm-forge' > "$state/wallpaper.selected"
OMAC_STATE_ROOT="$state" "$target_app/Contents/MacOS/AgentControlCenter" --prepare-runtime
codesign --verify --deep --strict "$target_app"
print "Omac installed. Backup: $backup"
major="$(sw_vers -productVersion | cut -d. -f1)"
permission_name='Accessibility'
(( major < 27 )) || permission_name='Device Control and Data Access'
print "Open Omac from Applications. Approve $permission_name for Omac and AeroSpace when prompted."
print 'Login startup stays off until you choose Start Omac at Login.'
# A successful install should open setup; tests/remote staging can suppress launch.
if [[ "${OMAC_NO_LAUNCH:-0}" == 0 ]]; then open "$target_app"; fi
