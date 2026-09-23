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
mkdir -p "${target_app:h}" "$backup" "$saver_dir"
app_existed=0; state_existed=0; saver_existed=0; mutation_started=0
[[ ! -e "$target_app" ]] || { ditto "$target_app" "$backup/Omac.app"; app_existed=1; }
[[ ! -e "$state" ]] || { ditto "$state" "$backup/state"; state_existed=1; }
[[ ! -e "$saver_dir/OMAC.saver" ]] || { ditto "$saver_dir/OMAC.saver" "$backup/OMAC.saver"; saver_existed=1; }
wait_for_active() {
 local aerospace="$1" expected_config="$2" expected_pages="${3:-}" attempt stable=0 degraded=0 windows_json missing
 for (( attempt=0; attempt<48; attempt++ )); do
  local job_info config_path
  job_info="$(launchctl print "gui/$(id -u)/com.richard.acc.aerospace" 2>/dev/null || true)"
  config_path="$("$aerospace" config --config-path 2>/dev/null || true)"
  # A returned config path and focused-workspace query prove the server answers,
  # and that launchd started the job with Omac's generated configuration.
  if [[ -r "$state/status" ]] && [[ "$(cat "$state/status")" == Active ]] &&
     [[ "$job_info" == *'state = running'* ]] &&
     [[ "$config_path" == "$expected_config" ]] &&
     "$aerospace" list-workspaces --focused >/dev/null 2>&1; then
   if windows_json="$("$aerospace" list-windows --all --format '%{window-id} %{app-pid}' --json 2>/dev/null)"; then
    if [[ -n "$windows_json" && "$windows_json" != '[]' ]]; then
     missing=0
     if [[ -n "$expected_pages" && -r "$expected_pages" ]]; then
      missing="$(/usr/bin/python3 - "$expected_pages" "$windows_json" <<'PY'
import json, sys
try:
    saved = json.load(open(sys.argv[1], encoding="utf-8"))
    current = json.loads(sys.argv[2])
    expected = {(str(w["window-id"]), str(w["app-pid"])) for w in saved.get("windows", [])
                if w.get("window-id") is not None and w.get("app-pid") is not None}
    live = {(str(w.get("window-id")), str(w.get("app-pid"))) for w in current}
    print(len(expected - live))
except Exception:
    print("invalid")
PY
)"
     fi
     if [[ "$missing" == 0 ]]; then
     (( stable += 1 ))
     (( stable >= 4 )) && return 0
     else
      degraded=1
      stable=0
     fi
    else
     degraded=1
     stable=0
    fi
   else
    stable=0
   fi
  else
   stable=0
  fi
  sleep 0.25
 done
 # A running, responsive, correctly configured server with no windows or with
 # missing saved window identities is degraded; retain files for recovery.
 # The install remains available for manual recovery instead of triggering a
 # rollback/re-engage cycle that can repeatedly disturb the user's session.
 (( degraded )) && return 2
 return 1
}
rollback() {
 local result=$? check_json python_cmd
 if (( result != 0 && mutation_started )); then
  # Keep the failed installation for diagnosis; restore the original paths.
  if [[ "${OMAC_REENGAGE_AFTER_INSTALL:-0}" == 1 ]]; then
   launchctl bootout "gui/$(id -u)/com.richard.acc.watcher" >/dev/null 2>&1 || true
   launchctl bootout "gui/$(id -u)/com.richard.acc.aerospace" >/dev/null 2>&1 || true
  fi
  [[ ! -e "$target_app" ]] || mv "$target_app" "$backup/failed-Omac.app"
  [[ ! -e "$state" ]] || mv "$state" "$backup/failed-state"
  [[ ! -e "$saver_dir/OMAC.saver" ]] || mv "$saver_dir/OMAC.saver" "$backup/failed-OMAC.saver"
  (( ! app_existed )) || ditto "$backup/Omac.app" "$target_app"
  (( ! state_existed )) || ditto "$backup/state" "$state"
  (( ! saver_existed )) || ditto "$backup/OMAC.saver" "$saver_dir/OMAC.saver"
  print -u2 "Installation failed; original files restored. Diagnostic backup: $backup"
  if [[ "${OMAC_REENGAGE_AFTER_INSTALL:-0}" == 1 ]] && (( app_existed )) &&
     [[ -x "$target_app/Contents/MacOS/AgentControlCenter" ]]; then
   if OMAC_STATE_ROOT="$state" "$target_app/Contents/MacOS/AgentControlCenter" --prepare-runtime >/dev/null 2>&1 &&
      check_json="$(OMAC_STATE_ROOT="$state" "$target_app/Contents/MacOS/AgentControlCenter" --check 2>/dev/null)" &&
      python_cmd="$(print -r -- "$check_json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["python"])')" &&
      aerospace_cli="$(print -r -- "$check_json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["aerospace"])')" &&
      OMAC_STATE_ROOT="$state" "$python_cmd" "$target_app/Contents/Resources/Payload/control.py" enter >/dev/null 2>&1 &&
      wait_for_active "$aerospace_cli" "$state/runtime/config/aerospace.toml" "$backup/state/pages.json"; then
    if [[ -e "$state/menu.enabled" ]] && ! launchctl print "gui/$(id -u)/com.richard.acc.menu" >/dev/null 2>&1; then
     launchctl bootstrap "gui/$(id -u)" "$state/runtime/launchd/menu.plist" || true
    fi
    print -u2 'Previous Omac installation returned to Active.'
   else
    print -u2 'Previous Omac installation was restored but could not re-engage automatically; use Enter Omac before switching pages.'
   fi
  fi
 fi
}
trap rollback EXIT
mutation_started=1
[[ ! -e "$target_app" ]] || mv "$target_app" "$backup/replaced-Omac.app"
ditto "$source_app" "$target_app"
[[ ! -e "$saver_dir/OMAC.saver" ]] || mv "$saver_dir/OMAC.saver" "$backup/replaced-OMAC.saver"
# Retire the old Omac screensaver on upgrade. The static wallpaper collection
# does not install or select a replacement; the backup remains reversible.
mkdir -p "$state"
[[ -e "$state/wallpaper.selected" ]] || print -n 'silver-ice' > "$state/wallpaper.selected"
OMAC_STATE_ROOT="$state" "$target_app/Contents/MacOS/AgentControlCenter" --prepare-runtime
codesign --verify --deep --strict "$target_app"
if [[ "${OMAC_REENGAGE_AFTER_INSTALL:-0}" == 1 ]]; then
 check_json="$(OMAC_STATE_ROOT="$state" "$target_app/Contents/MacOS/AgentControlCenter" --check)"
 python_cmd="$(print -r -- "$check_json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["python"])')"
 OMAC_STATE_ROOT="$state" "$python_cmd" "$target_app/Contents/Resources/Payload/control.py" enter
 aerospace_cli="$(print -r -- "$check_json" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["aerospace"])')"
 # AeroSpace's startup callback can briefly set status to Recovering after
 # enter returns. Give it time to become Active and answer with Omac's config.
 if wait_for_active "$aerospace_cli" "$state/runtime/config/aerospace.toml" "$backup/state/pages.json"; then
  :
 else
  gate_result=$?
  if (( gate_result == 2 )); then
   mutation_started=0
   print -u2 'Omac installed in a degraded state: AeroSpace is responsive with Omac config, but saved windows are missing. Use Enter Omac to recover the expected window state.'
  else
   print -u2 'Omac did not return to Active after installation.'
   exit 1
  fi
 fi
fi
print "Omac installed. Backup: $backup"
if [[ "${OMAC_REENGAGE_AFTER_INSTALL:-0}" != 1 ]]; then
 print 'Omac remains disengaged. Choose Enter Omac and verify its page controls before using remote switching.'
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
permission_name='Accessibility'
(( major < 27 )) || permission_name='Device Control and Data Access'
print "Open Omac from Applications. Approve $permission_name for Omac and AeroSpace when prompted."
print 'Login startup stays off until you choose Start Omac at Login.'
# A successful install should open setup; tests/remote staging can suppress launch.
if [[ "${OMAC_NO_LAUNCH:-0}" == 0 ]]; then open "$target_app"; fi
